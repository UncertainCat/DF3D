// GPU equivalent of actor_animation_catalog.gd; animation codes follow DEFINITIONS:
// 1 walk, 2 run, 3 climb, 4 stairs, 5 fall, 6 land, 7 work_mine,
// 8 work_chop, 9 work_craft, 10 eat, 11 drink, 12 haul, 13 attack,
// 14 flinch, 15 death, 16 idle, 17 sleep, 18 hop, 19 scurry,
// 20 lumber, 21 fly, 22 shoot. Zero disables animation.
// Input cutout artwork lies in x/-z; y is its physical thickness.
// Foot pivot is z=.5 in every style. Offset units match the CPU catalog.

float actor_animation_duration(int code) {
	if (code == 1) return .64;
	if (code == 2) return .40;
	if (code == 3) return .92;
	if (code == 4) return .70;
	if (code == 5) return .80;
	if (code == 6) return .34;
	if (code == 7) return .90;
	if (code == 8) return 1.10;
	if (code == 9) return .78;
	if (code == 10) return 1.35;
	if (code == 11) return 1.80;
	if (code == 12) return .88;
	if (code == 13) return .44;
	if (code == 14) return .22;
	if (code == 15) return .72;
	if (code == 16) return 4.80;
	if (code == 17) return 3.20;
	if (code == 18) return .58;
	if (code == 19) return .30;
	if (code == 20) return 1.05;
	if (code == 22) return .25;
	return 1.30;
}

vec3 actor_animate(vec3 vertex, float animation_code, float elapsed, float seed, bool upright) {
	int code = int(round(animation_code));
	if (code < 1 || code > 22) return vertex;
	bool looping = code != 6 && code != 13 && code != 14 && code != 15 && code != 22;
	float duration = actor_animation_duration(code);
	float u = looping ? fract(max(elapsed, 0.0) / duration + seed) : clamp(elapsed / duration, 0.0, 1.0);
	float wave = sin(u * 6.28318530718);
	float twice = sin(u * 12.56637061436);
	float bounce = .5 - .5 * cos(u * 12.56637061436);
	vec3 offset = vec3(0.0);
	float angle = 0.0;
	vec2 stretch = vec2(1.0);
	if (code == 1 || code == 2 || code == 12 || code == 19 || code == 20) {
		float amplitude = .035;
		float tilt = .055;
		if (code == 2) { amplitude = .075; tilt = .105; }
		if (code == 12) { amplitude = .020; tilt = .070; }
		if (code == 19) { amplitude = .025; tilt = .040; }
		if (code == 20) { amplitude = .025; tilt = .095; }
		offset.y = amplitude * bounce;
		angle = tilt * wave;
		stretch = vec2(1.0 - .015 * twice, 1.0 + .015 * twice);
	} else if (code == 3) {
		offset.x = .025 * wave;
		offset.y = .045 * bounce;
		angle = .095 * wave;
		stretch.y = 1.0 + .025 * twice;
	} else if (code == 4) {
		offset.y = .045 * bounce;
		angle = .035 * wave;
	} else if (code == 5) {
		angle = .055 * wave;
		stretch = vec2(.95, 1.06);
	} else if (code == 6) {
		float impact = smoothstep(0.0, .20, u) * (1.0 - smoothstep(.20, 1.0, u));
		stretch = vec2(1.0 + .12 * impact, 1.0 - .16 * impact);
	} else if (code == 7 || code == 8) {
		float windup = smoothstep(.05, .48, u) * (1.0 - smoothstep(.48, .63, u));
		float strike = smoothstep(.48, .63, u) * (1.0 - smoothstep(.63, .95, u));
		float strength = code == 7 ? 1.0 : 1.3;
		angle = strength * (-.10 * windup + .14 * strike);
		stretch.y = 1.0 - .06 * strike;
		offset.z = .025 * strike;
	} else if (code == 9) {
		float dip = .5 - .5 * cos(u * 6.28318530718);
		angle = .025 * wave;
		stretch.y = 1.0 - .04 * dip;
	} else if (code == 10) {
		float nod = pow(.5 - .5 * cos(u * 6.28318530718), 3.0);
		angle = .035 * nod;
		stretch.y = 1.0 - .035 * nod;
	} else if (code == 11) {
		float lift = smoothstep(.05, .30, u) * (1.0 - smoothstep(.65, .95, u));
		angle = -.07 * lift;
		stretch.y = 1.0 + .025 * lift;
	} else if (code == 13) {
		float lunge = smoothstep(.28, .48, u) * (1.0 - smoothstep(.48, 1.0, u));
		stretch.y = 1.0 - .045 * lunge;
	} else if (code == 14) {
		float recoil = smoothstep(0.0, .20, u) * (1.0 - smoothstep(.20, 1.0, u));
		angle = -.12 * recoil;
		stretch = vec2(1.0 + .035 * recoil, 1.0 - .035 * recoil);
	} else if (code == 22) {
		float recoil = smoothstep(0.0, .16, u) * (1.0 - smoothstep(.16, 1.0, u));
		angle = -.045 * recoil;
		stretch.y = 1.0 - .02 * recoil;
	} else if (code == 15) {
		float buckle = smoothstep(0.0, .32, u);
		float collapse = smoothstep(.18, .94, u);
		angle = -1.570796326795 * collapse;
		stretch.y = 1.0 - .12 * buckle;
	} else if (code == 16) {
		angle = .012 * wave;
		stretch.y = 1.0 + .006 * twice;
	} else if (code == 17) {
		stretch = vec2(1.0 + .009 * wave, 1.0 + .018 * wave);
	} else if (code == 18) {
		float lift = pow(.5 - .5 * cos(u * 6.28318530718), 1.5);
		offset.y = .14 * lift;
		stretch = vec2(1.0 - .04 * lift, 1.0 + .05 * lift);
	} else if (code == 21) {
		offset.y = .045 * wave;
		angle = .035 * sin(u * 6.28318530718 + .5);
	}
	// Upright conversion remains the caller's responsibility. The same artwork
	// Deformation is valid in Classic and camera-facing billboards.
	vec2 art = vec2(vertex.x, .5 - vertex.z) * stretch;
	float c = cos(angle);
	float s = sin(angle);
	art = vec2(c * art.x - s * art.y, s * art.x + c * art.y) + offset.xy;
	return vec3(art.x, vertex.y + offset.z, .5 - art.y);
}
