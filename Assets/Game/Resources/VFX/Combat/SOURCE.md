# Combat Feedback Assets

Created 2026-10-05 for the built-in-renderer, low-poly battle scene.

- Textures are references to the existing `VFX/FlyingSword` assets. Three neutral-tint materials are cloned here so original cyan sword materials remain unchanged.
- Original textures: Kenney Particle Pack, https://kenney.nl/assets/particle-pack . Creator page states CC0.
- Imported mapping and license file: `../FlyingSword/SOURCE.txt` and `../FlyingSword/Kenney_ParticlePack_License.txt`.
- New authored particle timing, colors, burst counts and prefab composition use the existing `SwordHitVFX.prefab` as a template. No new third-party download or purchase.
- Existing projectile prefabs remain projectile visuals, not explosion substitutes.
- All new systems are non-looping, <= 0.7 seconds particle lifetime, <= 32 particles per system, StopAction.None. VFXManager handles pooled reset and recycle.
- BeamLine.mat uses Unity's built-in Sprites/Default shader and vertex colors; shared by venom beams and lightning chains instead of an unassigned purple material.
- Ground explosion template has unit-scale footprint; WeaponSystem scales it by the actual AOE radius. The existing attack still resolves around the player; this patch does not turn it into a thrown projectile.
- Common feedback: restrained amber hit, stronger gold critical, green-gray normal death, gold elite death, red boss death, red player hurt; fire orange, lightning cyan, venom green, upgrade pale green-gold.

Generation trace: `C:/Unity_1/tools/battle_feedback_assets.cs.txt`. Existing source GUIDs and textures are preserved.
