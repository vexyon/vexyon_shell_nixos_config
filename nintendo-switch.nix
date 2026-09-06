# ---------------------------------------------------------------------------
# Captura de la Nintendo Switch (HDMI -> USB) para vxsh
# ---------------------------------------------------------------------------
#
# El cacharro es un pincho "UGREEN 15390", que por dentro es un MacroSilicon
# MS2130 conectado a USB 3.0 (SuperSpeed). Un solo dispositivo USB expone DOS
# funciones independientes:
#
#   interfaz 0/1  UVC  -> uvcvideo      -> /dev/videoN   : el vídeo
#   interfaz 2/3  UAC  -> snd-usb-audio -> tarjeta ALSA N: el audio del HDMI
#
# A diferencia de los MS2109 baratos (USB 2.0, que solo dan 1080p vía MJPEG y
# por eso arrastran latencia de compresión), este chip entrega 1920x1080@60 en
# YUYV 4:2:2 SIN COMPRIMIR. Comprobado con v4l2-ctl: 59,6 fps sostenidos y cero
# frames perdidos. Por eso `playswitch` fuerza yuyv422 explícitamente: el
# formato POR DEFECTO del dispositivo es MJPEG 1080p30, que es peor por los dos
# lados (mitad de framerate y un decodificador JPEG en medio).
#
# --- Identificación estable ------------------------------------------------
# Nada aquí referencia /dev/videoN, hw:N, el índice de tarjeta ALSA ni el id de
# objeto de PipeWire: todos ésos se reordenan al enchufar o desenchufar
# cualquier otro USB. Todo cuelga de los descriptores USB del propio aparato
# (fabricante + producto + número de serie), a través de los enlaces by-id que
# udev crea a partir de ellos.
#
# Se usan los by-id ESTÁNDAR de systemd en vez de un SYMLINK propio a
# propósito: `nixos-rebuild switch` recarga las reglas udev pero NO reproduce
# los eventos de los dispositivos ya enchufados, así que un enlace nuestro no
# aparecería hasta reiniciar o desenchufar la capturadora. Los by-id de systemd
# ya existen desde que se conectó el aparato y no dependen de ningún evento
# posterior, así que un rebuild no puede dejarlos a medias.

{ config, lib, pkgs, ... }:

let
  # --- La identidad del hardware, en un solo sitio -------------------------
  # (vendor 345f = MACROSILICON, product 2131 = MS2130)
  usbId = "MACROSILICON_UGREEN_15390_82370521";

  videoDev = "/dev/v4l/by-id/usb-${usbId}-video-index0"; # index1 es metadatos
  alsaCtl = "/dev/snd/by-id/usb-${usbId}-02";

  # --- La sesión de juego ---------------------------------------------------
  #
  # `playswitch` es el comando de "me pongo a jugar": abre el vídeo, enciende el
  # audio, y al cerrar la terminal (o al salir de mpv) lo deja TODO como estaba.
  #
  # El audio se enciende y apaga en el propio hardware. El MS2130 tiene un
  # conmutador de captura ('Digital In Capture Switch') y ningún control de
  # volumen; con el conmutador apagado la PCM entrega CEROS DIGITALES EXACTOS
  # (medido: 0 muestras distintas de cero de 333.824). O sea que apagarlo es
  # silencio de verdad, no un volumen a cero. No hace falta root: udev le da al
  # usuario de la sesión una ACL sobre el nodo de control de la tarjeta.
  #
  # Lo que se guarda y se restaura es el estado PREVIO del conmutador, no un
  # "apagado" fijo: si algún día lo dejas encendido a mano para oír la consola
  # sin abrir la ventana, `playswitch` te lo respeta al salir.
  #
  # Sobre la latencia del vídeo, en orden de impacto:
  #
  #   --demuxer-lavf-o=input_format=yuyv422,...
  #       Sin esto el driver entrega su formato por defecto (MJPEG 1080p30) y
  #       se paga un decodificador JPEG por frame. Con yuyv422 mpv reporta
  #       "rawvideo 1920x1080 60 fps": no hay decodificación, solo conversión
  #       de color en la GPU.
  #   --untimed
  #       Cada frame se presenta en cuanto llega, sin esperar a su timestamp.
  #       Es lo correcto en captura en vivo: los timestamps del dispositivo
  #       solo servirían para reintroducir el retardo que queremos quitar.
  #   --profile=low-latency
  #       Perfil de mpv: fflags=+nobuffer en libavformat, sin caché, sin
  #       interpolación, video-latency-hacks.
  #   --cache=no
  #       Ninguna cola de demuxer entre el USB y el vídeo.
  #   --no-audio
  #       El audio NO pasa por mpv: va por su propio camino en PipeWire. Si mpv
  #       lo llevara, tendría que bufferizar vídeo para sincronizar con él, que
  #       es justo lo que sobra.
  #   --no-config
  #       Ignora ~/.config/mpv: un mpv.conf del usuario (caché, perfiles de
  #       calidad, interpolación) no puede colarse y añadir retardo por detrás.
  #
  # El suelo que queda es de hardware: el propio MS2130 acumula un frame antes
  # de mandarlo por USB. A 60 Hz eso son ~16 ms que ningún ajuste de software
  # puede quitar. Lo de arriba evita añadir nada encima.
  playswitch = pkgs.writeShellScriptBin "playswitch" ''
    set -uo pipefail

    amixer=${pkgs.alsa-utils}/bin/amixer
    PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.gnugrep pkgs.gnused ]}

    : "''${SWITCH_CAPTURE_SIZE:=1920x1080}"
    : "''${SWITCH_CAPTURE_FPS:=60}"
    : "''${SWITCH_CAPTURE_FORMAT:=yuyv422}"

    if [ ! -e ${videoDev} ]; then
      echo "playswitch: no encuentro la capturadora." >&2
      echo "  falta ${videoDev}" >&2
      echo "  ¿está enchufada?" >&2
      exit 1
    fi

    # --- audio: encender la captura, recordando cómo estaba ------------------
    # El número de tarjeta ALSA es justo lo que NO es estable, así que se
    # resuelve desde el enlace by-id (que sí lo es): controlC<N> -> N.
    card=""
    control=""
    if [ -e ${alsaCtl} ]; then
      ctl=$(basename "$(readlink -f ${alsaCtl})")
      card=''${ctl#controlC}

      control="Digital In"
      if ! "$amixer" -c "$card" sget "$control" >/dev/null 2>&1; then
        # Otro firmware podría llamarlo de otra forma. La tarjeta es la
        # capturadora y solo tiene controles de captura.
        control=$("$amixer" -c "$card" scontrols \
          | sed -n "s/^Simple mixer control '\(.*\)',[0-9]*$/\1/p" | head -1)
      fi
    fi

    previo=""
    if [ -n "$control" ]; then
      if "$amixer" -c "$card" sget "$control" 2>/dev/null | grep -q '\[on\]'; then
        previo=cap
      else
        previo=nocap
      fi
    else
      echo "playswitch: aviso — no puedo controlar el audio de la capturadora." >&2
      echo "  el vídeo sí va; revisa 'amixer -c N scontrols'." >&2
    fi

    limpiar() {
      if [ -n "''${mpv_pid:-}" ]; then
        kill "$mpv_pid" 2>/dev/null
        wait "$mpv_pid" 2>/dev/null
      fi
      # Dejar el conmutador de captura como estaba antes de entrar.
      if [ -n "$control" ] && [ -n "$previo" ]; then
        "$amixer" -c "$card" sset "$control" "$previo" >/dev/null 2>&1
      fi
    }
    trap limpiar EXIT INT TERM HUP

    if [ -n "$control" ]; then
      "$amixer" -c "$card" sset "$control" cap >/dev/null 2>&1 \
        || echo "playswitch: aviso — no pude encender la captura de audio." >&2
    fi

    echo "Nintendo Switch: $SWITCH_CAPTURE_SIZE @ $SWITCH_CAPTURE_FPS fps ($SWITCH_CAPTURE_FORMAT)"
    echo "Cierra la ventana, pulsa q, o cierra esta terminal para terminar."

    # mpv en segundo plano + wait, NO exec: hace falta seguir vivo para que el
    # trap devuelva el audio a su sitio cuando esto acabe.
    ${pkgs.mpv}/bin/mpv \
      --no-config \
      --profile=low-latency \
      --untimed \
      --cache=no \
      --demuxer-seekable-cache=no \
      --no-audio \
      --hwdec=no \
      --interpolation=no \
      --vo=gpu-next \
      --no-osc \
      --force-window=immediate \
      --title="Nintendo Switch" \
      --screenshot-directory="''${XDG_PICTURES_DIR:-$HOME/Pictures}" \
      --demuxer-lavf-o=input_format="$SWITCH_CAPTURE_FORMAT",video_size="$SWITCH_CAPTURE_SIZE",framerate="$SWITCH_CAPTURE_FPS" \
      "av://v4l2:${videoDev}" \
      "$@" &
    mpv_pid=$!
    wait "$mpv_pid"
  '';

  desktopItem = pkgs.makeDesktopItem {
    name = "playswitch";
    desktopName = "Nintendo Switch";
    comment = "Captura HDMI de la Switch";
    exec = "${playswitch}/bin/playswitch";
    icon = "applications-games";
    categories = [ "AudioVideo" "Video" "Game" ];
    keywords = [ "switch" "nintendo" "captura" "capture" "hdmi" "playswitch" ];
  };
in
{
  # --- PipeWire / WirePlumber -----------------------------------------------
  #
  # Objetivo: que el audio de la Switch salga por los auriculares y aparezca en
  # la pestaña STREAMS del mixer de vxsh, con su propio volumen, sin ensuciar
  # la pestaña Inputs (donde tiene que seguir estando solo el micro).
  #
  # Cómo funciona: vxsh clasifica los nodos de PipeWire por media.class
  #   Outputs -> Audio/Sink            (services/Audio.qml: isSink && !isStream)
  #   Inputs  -> Audio/Source          (services/Mic.qml:  !isSink && !isStream)
  #   Streams -> Stream/Output/Audio   (services/Audio.qml: isSink && isStream)
  #
  # Por defecto la capturadora es un Audio/Source y cae en Inputs, al lado del
  # micro. Aquí se le reetiqueta el media.class a Stream/Output/Audio: el nodo
  # ALSA de captura pasa a comportarse como un reproductor cualquiera, PipeWire
  # lo engancha solo al sink por defecto (los auriculares) y vxsh lo pinta en
  # Streams con volumen propio y persistente.
  #
  # Esto es UN SOLO nodo, no un loopback: no hay proceso intermedio ni un
  # segundo buffer entre la captura y la salida.
  #
  # Nada de esto toca al micro: las reglas van casadas contra el número de serie
  # USB de la capturadora y solo contra él.
  services.pipewire.wireplumber.extraConfig."51-nintendo-switch" = {
    "monitor.alsa.rules" = [
      {
        # ACP fuera. ACP es la capa de "perfiles y rutas" pensada para tarjetas
        # de sonido de verdad, y arrastra estado mutable: WirePlumber recuerda
        # perfil, ruta, volumen y MUTE por tarjeta en ~/.local/state y los
        # reaplica al arrancar. Justo eso es lo que dejaba esta entrada muteada.
        # La capturadora no tiene nada que elegir (una sola PCM de captura), así
        # que sin ACP el nodo sale siempre igual y no hay estado que restaurar.
        matches = [ { "device.name" = "~alsa_card\\.usb-${usbId}-.*"; } ];
        actions.update-props = {
          "api.alsa.use-acp" = false;
          "device.description" = "Nintendo Switch (capturadora HDMI)";
        };
      }
      {
        matches = [ { "node.name" = "~alsa_input\\.usb-${usbId}-.*"; } ];
        actions.update-props = {
          "media.class" = "Stream/Output/Audio";

          # vxsh etiqueta los streams con application.name si lo hay, y si no
          # con la descripción (modules/VolumePanel.qml -> Audio.streamLabel).
          "application.name" = "Nintendo Switch";
          "node.description" = "Nintendo Switch";
          "node.nick" = "Nintendo Switch";
          "media.name" = "Nintendo Switch";

          # Que PipeWire lo enganche solo al sink POR DEFECTO. Se deja que sea
          # el sink por defecto a propósito, en vez de fijar los auriculares
          # Corsair: si algún día se cambia de auriculares o se pasa al HDMI,
          # el audio de la Switch sigue el cambio como cualquier otro stream.
          "node.autoconnect" = true;

          # Sin esto el nodo se pararía al quedarse ocioso y la entrada del
          # mixer (y su volumen) aparecería y desaparecería sola.
          "node.pause-on-idle" = false;

          # 256 muestras a 48 kHz = 5,3 ms de buffer. Medido con pw-top: el
          # nodo corre a QUANT 256 con 0 xruns, sin arrastrar al resto del
          # grafo (Brave sigue a 1024). Si alguna vez crepitara, subir a
          # 512/48000.
          "node.latency" = "256/48000";
        };
      }
    ];
  };

  environment.systemPackages = [
    playswitch
    desktopItem
    pkgs.v4l-utils # v4l2-ctl, para diagnosticar la capturadora
    pkgs.alsa-utils # amixer, para mirar el conmutador de captura a mano
  ];
}
