# Atmospheric Scattering for URP
A physically based atmospheric scattering rendering solution, designed for mobile platforms and integrated into the Unity URP Pipeline, featuring time-of-day changes, ground-to-space views, multi-scattering, sun disk, and more.

![](Documentation~/Atmosphere2.gif)
![](Documentation~/Atmosphere1.png) 
![](Documentation~/Atmosphere2.png)

##  Development Log
[Development Log](https://jojo-lyu.notion.site/Atmosphere-Developing-0216c5732f3a40b78fa9847e79ba342d?pvs=4)
### Pipeline Integration

- [x]  Sky Only - Sky Box
- [ ]  Sky + Scene - Post Process for Opaque(AP) and Sky(AP or Sky View), Per-Vertex AP for Transparent
- [ ]  Outer Space - Raymarching

### Basic

- [x]  URP Pipeline Integration
- [x]  Atmosphere Config
- [x]  Transmittance LUT
- [x]  Multi Scattering LUT
- [x]  Sky View LUT
- [x]  Sky Box
- [x]  Sun Disk
- [ ]  Moon Disk
- [x]  Directional Light LUT
- [x]  Ambient Light LUT
- [x]  Ground Bounce
- [ ]  AP Support
- [x]  Ray March Pass
- [ ]  Refection Probe

### Optimization

- [ ]  Sky View- Octahedral Storing, and Abandoning Horizon Below
- [ ]  Multi Scattering - Pixel Shader Implementation, and Simplify Integration Rays(64 to 2)
- [x]  LUT Update Strategy - Data Triger
- [ ]  LUT Update Strategy -Support Multi-Frames,

## Folder Structure

Demo folder
  - Assets used in demo.
    
Scripts folder
  - **AtmosphereConfig**: configuration data for Atmosphere parameters.
  - **AtmosphereFeature**: interface for integrating into URP. The Execute method is the render entry point for every frame.
  - **AtmospherePrecomputeManager**: the core logic to execute all tasks.
  - **AtmosphereTools**: a set of tools.
    
Shaders folder
  - **AtmosphereCommon.hlsl**: data structures and tool sets.
  - **AtmosphereCore.hlsl**: core logic.
  - **AtmosphereRaymarch.shader**: render atmosphere, which is essentially a fullscreen render in post-process.
  - **AtmosphereSkyBox.shader**: used for the Skybox.
  - **SkyViewLut.shader**: render Sky-View LUT, only executed when atmosphere parameters change.
  - **TransmittanceLut.shader**: renders Transmittance LUT, only executed when atmosphere parameters change.
  - **AtmosphereMultiScatter.compute**: render multi-scattering LUT, only executed when atmosphere parameters change.

# References
- [Hillaire20] [A Scalable and Production Ready Sky and Atmosphere Rendering Technique](https://sebh.github.io/publications/egsr2020.pdf)
- [Bruneton08] [Precomputed Atmospheric Scattering](https://hal.inria.fr/inria-00288758/document)
- [Elek09] [Rendering Parametrizable Planetary Atmospheres with Multiple Scattering in Real-Time](http://www.cescg.org/CESCG-2009/papers/PragueCUNI-Elek-Oskar09.pdf)
- [Hillaire16] [Physically Based Sky, Atmosphere and Cloud Rendering in Frostbite](https://media.contentapi.ea.com/content/dam/eacom/frostbite/files/s2016-pbs-frostbite-sky-clouds-new.pdf)
- [Bruneton17] [Precomputed Atmospheric Scattering: a New Implementation](https://ebruneton.github.io/precomputed_atmospheric_scattering/)
- [Yusov13] [Outdoor Light Scattering Sample Update](https://www.intel.com/content/dam/develop/external/us/en/documents/outdoor-light-scattering-update.pdf)
- [ONe07] [“Accurate Atmospheric Scattering”. GPU Gems 2](https://developer.nvidia.com/gpugems/gpugems2/part-ii-shading-lighting-and-shadows/chapter-16-accurate-atmospheric-scattering)
- [NSTN93] [Display of The Earth Taking into Account Atmospheric Scattering](https://dl.acm.org/doi/pdf/10.1145/166117.166140)
- [NDKY96] [Display method of the sky color taking into account multiple scattering](http://nishitalab.org/user/nis/cdrom/skymul.pdf)
