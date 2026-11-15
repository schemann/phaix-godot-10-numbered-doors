# Numbered Doors in Godot 4

Project files for tutorial 10 of the Godot 4 series by Phaix on YouTube (https://www.youtube.com/@Phaix).

Put the room number on every door of a game like Roblox DOORS in Godot 4.
A Label3D on the swinging leaf, the number from the generator's plan, and a small number plate built from CSG shapes, lit by the room like the door.

The Label3D is a child of the door's hinge, so the number swings open with the door and no code moves it. Its digits are about 7 cm tall, read up close like the number on a real door. It floats one centimetre in front of the leaf: right on the face it z-fights, and the video shows why with the depth buffer's steps. The number comes from the plan (the room's index plus one, the room behind the door), never from a counter, so freed rooms, a restart and a new seed cannot make it wrong. Then a plate of CSG boxes and cylinders with a sunken field holds the number: shaded digits in a light beige, a Font Variation of the built in font, and four digits with %04d. Every step is its own project folder.

## Steps

Every step of the video is its own folder in `steps/`, the exact state at the end of that
part. Open the project in Godot 4.7, then open `steps/<step>/main.tscn` and press F6 to run
that step. The project's main scene is the final step.

| Folder | Part of the video |
|---|---|
| `steps/step_00_start` | Starting point (the final state of the previous tutorial) |
| `steps/step_01_label_on_the_leaf` | Step 1 - A Label3D on the leaf |
| `steps/step_02_numbers_from_the_chain` | Step 2 - The number comes from the plan |
| `steps/step_03_number_plate` | Step 3 - A number plate |

## Controls

WASD or arrow keys or the left stick to walk, mouse or right stick to look, Space to jump,
Esc gives the mouse back, a click captures it again. Further keys per tutorial are shown
in the video and in the HUD.

## Tests

```sh
godot --headless --path . -s res://tests/run_tests.gd
```

## Support

Support the channel: https://ko-fi.com/phaix or https://github.com/sponsors/schemann

## License

Code and scenes: MIT (see LICENSE).
The figure and its animations: Animated Characters Protagonists by Kenney (www.kenney.nl), CC0, see character/License.txt.
The sounds (footsteps, doors, lock, key): RPG Audio by Kenney (www.kenney.nl, https://kenney.nl/assets/rpg-audio), CC0, see sounds/CREDITS.md.
