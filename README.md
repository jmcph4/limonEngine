# LimonEngine

Limon is a multi platform 3D game engine mainly focusing on first person games. Focus of its development is ease of use and ease of study. 

## Feature Overview

- 3D rendering with dynamic lighting/shadows
- Rigid body physics
- 3D spatial sound
- AI
- Built-in editor with animation sequencer
- C++ API for extensibility, and dynamic loading of extensions

For details check out the [project web site](http://enginmanap.github.io/limonEngine/status.html)

Prebuilt binaries for Windows, Linux and MacOS can be [found here](https://github.com/enginmanap/limonEngine/releases)

Documentation is served on [readthedocs](https://limonengine.readthedocs.io/en/latest/)

For a demonstration, check out the video :

[![Mayan Map with sound](http://img.youtube.com/vi/1OHS3TJ1q6o/0.jpg)](http://www.youtube.com/watch?v=1OHS3TJ1q6o)

## Building

Dependencies can be installed on Ubuntu 17.10 using:

```bash
$ sudo apt-get install libassimp-dev libbullet-dev libsdl2-dev libsdl2-image-dev libfreetype6-dev libtinyxml2-dev libglew-dev build-essential libglm-dev libtinyxml2-dev gcc-multilib g++-multilib
```

After that, in repository directory
```bash
$ mkdir build
$ cd build
$ cmake ../
```

## Running

### Start up: 
- Engine take a parameter as path of world to load
- If no parameter passed, falls back to `./Data/Maps/World001.xml`

### In Application:
- Pressing `0` switches to debug mode, renders physics collision meshes and disconnects player from physics (flying and passing trough objects)
- Pressing `F2` key switches to editor mode, which allows creating maps.
- Pressing `+` and `-` changes mouse sensitivity.
- `wasd` for walking around and mouse for looking around as usual.

### In editor mode:
- Since static and dynamic objects rigidbodies are not generated by same logic, mass settings can't be changed after object creation.
- Inanimate objects are not allowed to have AI
- You can create animations for doors etc. in editor. For animation creation, time step is 60 for each second.
- When a new animation is created by animation editor, the object used to create the animation assumed to have this animation. You can remove by using the remove animation button.

### Extending with C++
- Engine tries to load custom trigger extentions as `libcustomTriggers.dll` for Windows, `libcustomTriggers.so` for GNU/Linux and `libcustomTriggers.dylib` for macOS. If you use a custom action in a map and library is missing, action won't run check this first.
- Custom actions should implement `TriggerInterface` class.
- and the list of actions should be returned with method `void registerAsTrigger(std::map<std::string, TriggerInterface*(*)(LimonAPI*)>* triggerMap);`, sample implementation in CoinPickUpOnTrigger
- If you query a variable that never been set, it will be returned as 0.
- Static values are saved when set in editor, other action results and variables are queried when action runs.
