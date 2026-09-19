<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

The project implements a 2D side-scrolling platformer with retro VHS visual effects using Verilog. It displays a playable character navigating across platforms, pits, and spikes on a VGA screen, complete with hardware-generated chromatic aberration and tracking static.

## How to test

Connect the FPGA to a VGA display and a gamepad then program the FPGA. Use the controls to move the player, jump over obstacles, and reach the end of the level to win.

Controls:
[0] LEFT
[1] RIGHT
[2] JUMP
[3] or [7] START / RESTART

## External hardware

FPGA development board
TinyVGA PMOD
Gamepad PMOD (optional)
VGA display
