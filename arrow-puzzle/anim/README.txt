layered_2_5_second_seamless_idle_loop_of — Spine 4.3 character animation (Bravebits Game Asset Studio)

Files: layered_2_5_second_seamless_idle_loop_of.spine-json (skeleton), layered_2_5_second_seamless_idle_loop_of.atlas (atlas, premultiplied alpha), one PNG page per layer (<layer>.png, PMA)
Animations: idle (2.5s, loop) · celebrate_win (1.6s) · tap_react (0.6s) · hit_react (0.4s)
Recommended: idle
Every layer is its own slot; glow/light layers use additive/screen blending, radial layers (rays, sparks) are duplicated around the center.
Size in Spine units = px @1x of the game resolution.

Godot 4 (spine-godot runtime 4.3): drop the folder into the project → layered_2_5_second_seamless_idle_loop_of.spine-json and layered_2_5_second_seamless_idle_loop_of.atlas are imported automatically →
  create a SpineSkeletonDataResource, set Atlas Res = layered_2_5_second_seamless_idle_loop_of.atlas and Skeleton File Res = layered_2_5_second_seamless_idle_loop_of.spine-json →
  add a SpineSprite node with that Skeleton Data Res → get_animation_state().set_animation("idle", true, 0).
