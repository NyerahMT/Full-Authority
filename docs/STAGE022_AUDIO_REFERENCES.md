# Stage 022 audio references

Stage 022's audio pass follows the architecture used by mature combat-flight sims rather than treating a jet as one synthesized noise source.

## DCS World

Public DCS sound definitions and modding material show aircraft audio split into independent sources/layers: engine front/side/back, distant jet, flyby, afterburner, wind, cockpit/internal sound, and discrete sonic-boom events. SDEFs provide per-source gain, radius/falloff, direction cones, and dynamic pitch/volume control. Heatblur's F-14 sound rework likewise replaced/added recorded samples, rebuilt sound definitions, and added code to make the mix respond dynamically.

References:
- https://modding.caffeinesimulations.com/UsefulBits/CockpitSounds/
- https://forum.dcs.world/topic/168563-just-another-sound-mod/
- https://forum.dcs.world/topic/166956-sound-modding-in-dcs/
- https://www.digitalcombatsimulator.com/en/news/changelog/release/2.9.6.57650/

## VTOL VR / Unity

VTOL VR is Unity-based. Its public modding ecosystem uses Unity audio assets/AudioSources, and VTOL VR changelogs explicitly distinguish individual audio sources, afterburner effects, sonic-boom sounds, and cockpit/canopy muffling. Unity's AudioSource supports independent clips, 3D placement, spatial blend, distance falloff and mixer routing.

References:
- https://vtolvr-mods.com/docs/creating-a-mod/setup/
- https://store.steampowered.com/news/posts/?appids=667970&enddate=1589644424&feed=steam_community_announcements
- https://docs.unity.cn/Manual/class-AudioSource.html

## Full Authority consequence

The target mix is therefore layered:
1. low-frequency engine/combustion core
2. subdued compressor/turbine cue
3. exhaust roar
4. independent afterburner roar/transient
5. airframe/wind layer
6. flyby/distance layer
7. discrete sonic-boom event

Stage 022 implements those responsibilities as separate AVAudioEngine nodes for the menu events and reduces the gameplay compressor/noise dominance. The next major audio step should replace synthetic fallback loops with curated recorded clips where redistribution licensing is clean.

Useful clean-source candidates identified during research:
- Sandermotions F-16 takeoff recordings on Freesound, CC0: https://freesound.org/people/Sandermotions/sounds/276291/
- U.S. Air Force F-16 takeoff video/audio, public domain: https://commons.wikimedia.org/wiki/File:Exercise_Sprint_26-2_F-16_Take_Offs_(993056).webm
- Sonic-boom field recording on Wikimedia Commons, CC BY 3.0: https://commons.wikimedia.org/wiki/File:Sonic-boom-massive-sound.ogg
