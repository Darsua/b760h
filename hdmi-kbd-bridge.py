#!/usr/bin/env python3
"""
Lightweight USB Keyboard to HDMI Tmux Bridge for ZTE B760H
Captures USB keyboard events via evdev and injects into tmux session 'hdmi'.
"""

import os
import sys
import time
import subprocess
import select
import evdev
from evdev import ecodes

TMUX_SOCKET = "/tmp/tmux-1000/default"

KEYMAP = {
    ecodes.KEY_A: ('a', 'A'), ecodes.KEY_B: ('b', 'B'), ecodes.KEY_C: ('c', 'C'),
    ecodes.KEY_D: ('d', 'D'), ecodes.KEY_E: ('e', 'E'), ecodes.KEY_F: ('f', 'F'),
    ecodes.KEY_G: ('g', 'G'), ecodes.KEY_H: ('h', 'H'), ecodes.KEY_I: ('i', 'I'),
    ecodes.KEY_J: ('j', 'J'), ecodes.KEY_K: ('k', 'K'), ecodes.KEY_L: ('l', 'L'),
    ecodes.KEY_M: ('m', 'M'), ecodes.KEY_N: ('n', 'N'), ecodes.KEY_O: ('o', 'O'),
    ecodes.KEY_P: ('p', 'P'), ecodes.KEY_Q: ('q', 'Q'), ecodes.KEY_R: ('r', 'R'),
    ecodes.KEY_S: ('s', 'S'), ecodes.KEY_T: ('t', 'T'), ecodes.KEY_U: ('u', 'U'),
    ecodes.KEY_V: ('v', 'V'), ecodes.KEY_W: ('w', 'W'), ecodes.KEY_X: ('x', 'X'),
    ecodes.KEY_Y: ('y', 'Y'), ecodes.KEY_Z: ('z', 'Z'),
    ecodes.KEY_1: ('1', '!'), ecodes.KEY_2: ('2', '@'), ecodes.KEY_3: ('3', '#'),
    ecodes.KEY_4: ('4', '$'), ecodes.KEY_5: ('5', '%'), ecodes.KEY_6: ('6', '^'),
    ecodes.KEY_7: ('7', '&'), ecodes.KEY_8: ('8', '*'), ecodes.KEY_9: ('9', '('),
    ecodes.KEY_0: ('0', ')'),
    ecodes.KEY_MINUS: ('-', '_'), ecodes.KEY_EQUAL: ('=', '+'),
    ecodes.KEY_LEFTBRACE: ('[', '{'), ecodes.KEY_RIGHTBRACE: (']', '}'),
    ecodes.KEY_BACKSLASH: ('\\', '|'), ecodes.KEY_SEMICOLON: (';', ':'),
    ecodes.KEY_APOSTROPHE: ("'", '"'), ecodes.KEY_GRAVE: ('`', '~'),
    ecodes.KEY_COMMA: (',', '<'), ecodes.KEY_DOT: ('.', '>'),
    ecodes.KEY_SLASH: ('/', '?'), ecodes.KEY_SPACE: (' ', ' '),
}

SPECIAL_KEYS = {
    ecodes.KEY_ENTER: 'Enter',
    ecodes.KEY_KPENTER: 'Enter',
    ecodes.KEY_BACKSPACE: 'BSpace',
    ecodes.KEY_TAB: 'Tab',
    ecodes.KEY_ESC: 'Escape',
    ecodes.KEY_UP: 'Up',
    ecodes.KEY_DOWN: 'Down',
    ecodes.KEY_LEFT: 'Left',
    ecodes.KEY_RIGHT: 'Right',
    ecodes.KEY_HOME: 'Home',
    ecodes.KEY_END: 'End',
    ecodes.KEY_PAGEUP: 'PPage',
    ecodes.KEY_PAGEDOWN: 'NPage',
    ecodes.KEY_DELETE: 'DC',
    ecodes.KEY_INSERT: 'IC',
}

def send_key(key, literal=False):
    cmd = ["tmux"]
    if os.path.exists(TMUX_SOCKET):
        cmd.extend(["-S", TMUX_SOCKET])
    cmd.extend(["send-keys", "-t", "hdmi"])
    if literal:
        cmd.extend(["-l", key])
    else:
        cmd.append(key)
    try:
        subprocess.run(cmd, check=False)
    except Exception:
        pass

def find_keyboards():
    keyboards = []
    for path in evdev.list_devices():
        try:
            dev = evdev.InputDevice(path)
            caps = dev.capabilities()
            if ecodes.EV_KEY in caps:
                keys = caps[ecodes.EV_KEY]
                if ecodes.KEY_A in keys and ecodes.KEY_SPACE in keys:
                    keyboards.append(dev)
        except Exception:
            continue
    return keyboards

def main():
    shift_pressed = False
    ctrl_pressed = False
    alt_pressed = False
    caps_lock = False

    while True:
        keyboards = find_keyboards()
        if not keyboards:
            time.sleep(1)
            continue

        dev_fds = {dev.fd: dev for dev in keyboards}

        try:
            while True:
                r, _, _ = select.select(dev_fds.keys(), [], [], 2.0)
                if not r:
                    # Check for hotplug changes
                    current_paths = evdev.list_devices()
                    if len(current_paths) != len(keyboards):
                        break
                    continue

                for fd in r:
                    dev = dev_fds.get(fd)
                    if not dev:
                        continue
                    try:
                        for event in dev.read():
                            if event.type != ecodes.EV_KEY:
                                continue

                            code = event.code
                            val = event.value  # 0=release, 1=press, 2=repeat

                            # Track modifier states
                            if code in (ecodes.KEY_LEFTSHIFT, ecodes.KEY_RIGHTSHIFT):
                                shift_pressed = (val != 0)
                                continue
                            if code in (ecodes.KEY_LEFTCTRL, ecodes.KEY_RIGHTCTRL):
                                ctrl_pressed = (val != 0)
                                continue
                            if code in (ecodes.KEY_LEFTALT, ecodes.KEY_RIGHTALT):
                                alt_pressed = (val != 0)
                                continue
                            if code == ecodes.KEY_CAPSLOCK and val == 1:
                                caps_lock = not caps_lock
                                continue

                            # Only process key presses and repeats
                            if val == 0:
                                continue

                            # Handle Ctrl combinations (e.g. Ctrl-C, Ctrl-D, Ctrl-L)
                            if ctrl_pressed:
                                if code in KEYMAP:
                                    char = KEYMAP[code][0].lower()
                                    send_key(f"C-{char}")
                                elif code in SPECIAL_KEYS:
                                    send_key(f"C-{SPECIAL_KEYS[code]}")
                                continue

                            # Handle Special Keys (Enter, Backspace, Arrows, Tab, etc.)
                            if code in SPECIAL_KEYS:
                                send_key(SPECIAL_KEYS[code])
                                continue

                            # Handle standard printable characters
                            if code in KEYMAP:
                                norm, shifted = KEYMAP[code]
                                use_shifted = shift_pressed
                                if norm.isalpha() and caps_lock:
                                    use_shifted = not use_shifted
                                char = shifted if use_shifted else norm
                                send_key(char, literal=True)
                    except (OSError, IOError):
                        # Device disconnected
                        break
                else:
                    continue
                break
        except Exception:
            time.sleep(1)

if __name__ == '__main__':
    main()
