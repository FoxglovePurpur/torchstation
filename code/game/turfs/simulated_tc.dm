/turf/simulated
	var/datum/sunlight_handler/shandler

/turf/simulated/New()
	. = ..()

/turf/simulated/Initialize(mapload)
	. = ..()
	if(mapload)
		return INITIALIZE_HINT_LATELOAD

/turf/simulated/LateInitialize()
	if((SSplanets && SSplanets.z_to_planet.len >= z && SSplanets.z_to_planet[z]) && has_dynamic_lighting()) //ONLY FOR PLANET TILES IGNORE FAKESUN TILES
		if(is_outdoors())
			var/turf/T = GetAbove(src)
			if(T && !istype(T,/turf/simulated/open))
				make_indoors()
		shandler = new(src)
		shandler.manualInit()

/datum/sunlight_handler
	var/datum/sun_holder/sun
	var/turf/simulated/holder
	var/datum/lighting_object/only_sun_object
	var/effect_str_r = 0
	var/effect_str_g = 0
	var/effect_str_b = 0
	var/list/datum/lighting_corner/affected = list()
	var/list/datum/lighting_corner/only_sun = list()
	var/sunlight = FALSE
	var/inherited = FALSE

/datum/sunlight_handler/New(var/parent)
	. = ..()
	holder = parent

//Moved initialization here to make sure that it doesn't happen too early when replacing turfs.
/datum/sunlight_handler/proc/manualInit()
	if(!holder.lighting_corners_initialised)
		holder.generate_missing_corners()
	var/corners = list(holder.lighting_corner_NE,holder.lighting_corner_NW,holder.lighting_corner_SE,holder.lighting_corner_SW)
	for(var/datum/lighting_corner/corner in corners)
		if(corner.sunlight == SUNLIGHT_NONE)
			corner.sunlight = SUNLIGHT_POSSIBLE
	if(SSplanets && SSplanets.z_to_planet.len >= holder.z && SSplanets.z_to_planet[holder.z])
		var/datum/planet/planet = SSplanets.z_to_planet[holder.z]
		sun = planet.sun_holder
	sunlight_check()

/datum/sunlight_handler/proc/holder_change()
	sunlight_update()
	for(var/dir in (cardinal + cornerdirs))
		var/turf/simulated/T = get_step(holder, dir)
		if(istype(T) && T.shandler)
			T.shandler.sunlight_update()
	sunlight_update()
	//Might seem silly and unoptimized to call update twice, but this is not called frequently and it makes things easier.
	//Logical flow goes:
	//Update 1: Disowns the lighting corner
	//Update surrounding turfs: Allows for corner to be claimed by other sunlight handler
	//Update 2: Accounts for changes made by surrounding turfs


/datum/sunlight_handler/proc/turf_update(var/old_density, var/turf/new_turf, var/above)
	if(above)
		sunlight_check()
		sunlight_update()
		return
	if(new_turf.density && !old_density && sunlight) //This has the potential to cut off our sunlight
		sunlight_check()
		sunlight_update()
	else if (!new_turf.density && old_density && !sunlight) //This has the potential to introduce sunlight
		sunlight_check()
		sunlight_update()

/datum/sunlight_handler/proc/sunlight_check()
	var/cur_sunlight = sunlight
	if(holder.is_outdoors())
		sunlight = SUNLIGHT_OVERHEAD
	if(holder.density)
		sunlight = FALSE
	if(holder.check_for_sun() && !holder.is_outdoors() && !holder.density)
		var/outside_near = FALSE
		outer_loop:
			for(var/dir in cardinal)
				var/steps = 1
				var/turf/cur_turf = get_step(holder,dir)
				while(cur_turf && !cur_turf.density && steps < (SUNLIGHT_RADIUS + 1))
					if(cur_turf.is_outdoors())
						outside_near = TRUE
						break outer_loop
					steps += 1
					cur_turf = get_step(cur_turf,dir)
		if(!outside_near) //If cardinal directions fail, then check diagonals.
			var/radius = ONE_OVER_SQRT_2 * SUNLIGHT_RADIUS + 1
			outer_loop:
				for(var/dir in cornerdirs)
					var/steps = 1
					var/turf/cur_turf = get_step(holder,dir)
					var/opp_dir = turn(dir,180)
					var/north_south = opp_dir & (NORTH|SOUTH)
					var/east_west = opp_dir & (EAST|WEST)

					while(cur_turf && !cur_turf.density && steps < radius)
						var/turf/vert_behind = get_step(cur_turf,north_south)
						var/turf/hori_behind = get_step(cur_turf,east_west)
						if(vert_behind.density && hori_behind.density) //Prevent light from passing infinitesimally small gaps
							break outer_loop
						if(cur_turf.is_outdoors())
							outside_near = TRUE
							break outer_loop
						steps += 1
						cur_turf = get_step(cur_turf,dir)
		if(outside_near)
			sunlight = TRUE
		else if(sunlight)
			sunlight = FALSE

	if(cur_sunlight != sunlight)
		sunlight_update()
		if(!sunlight)
			SSlighting.sunlight_queue -= src
		else
			SSlighting.sunlight_queue += src

/datum/sunlight_handler/proc/sunlight_update()
	var/list/corners = list(holder.lighting_corner_NE,holder.lighting_corner_NW,holder.lighting_corner_SE,holder.lighting_corner_SW)
	var/list/new_corners = list()
	var/list/removed_corners = list()
	var/sunlightonly_corners = 0
	for(var/datum/lighting_corner/corner in corners)
		switch(corner.sunlight)
			if(SUNLIGHT_NONE)
				if(sunlight)
					corner.sunlight = SUNLIGHT_CURRENT
					new_corners += corner
				else
					corner.sunlight = SUNLIGHT_POSSIBLE
			if(SUNLIGHT_POSSIBLE)
				if(sunlight)
					corner.sunlight = SUNLIGHT_CURRENT
					new_corners += corner
			if(SUNLIGHT_CURRENT)
				if(!sunlight && (corner in affected))
					affected -= corner
					removed_corners += corner
					corner.sunlight = SUNLIGHT_POSSIBLE
			if(SUNLIGHT_ONLY)
				sunlightonly_corners++
				if(!(sunlight == SUNLIGHT_OVERHEAD) && (corner in only_sun))
					only_sun -= corner
					sunlightonly_corners--
					if(sunlight)
						new_corners += corner
						corner.sunlight = SUNLIGHT_CURRENT
						continue
					corner.lum_r = 0
					corner.lum_g = 0
					corner.lum_b = 0

	if(!sun)
		if(SSplanets && SSplanets.z_to_planet.len >= holder.z && SSplanets.z_to_planet[holder.z])
			var/datum/planet/planet = SSplanets.z_to_planet[holder.z]
			sun = planet.sun_holder
		else
			return

	if(sunlight == SUNLIGHT_OVERHEAD)
		for(var/datum/lighting_corner/corner in affected)
			if(!LAZYLEN(corner.affecting))
				affected -= corner
				removed_corners += corner
				only_sun += corner
				corner.sunlight = SUNLIGHT_ONLY
		for(var/datum/lighting_corner/corner in new_corners)
			if(!LAZYLEN(corner.affecting))
				new_corners -= corner
				only_sun += corner
				corner.sunlight = SUNLIGHT_ONLY

	if(sunlightonly_corners == 4 && !only_sun_object)
		var/datum/lighting_object/holder_object = holder.lighting_object
		if(holder_object && !holder_object.sunlight_only)
			only_sun_object = holder_object
			only_sun_object.sunlight_only = TRUE

	if(sunlightonly_corners < 4 && only_sun_object)
		only_sun_object.sunlight_only = FALSE
		only_sun_object = null

	if(only_sun_object)
		only_sun_object.update_sun()

	for(var/datum/lighting_corner/corner in only_sun)
		corner.update_sun()

	if(!affected.len && !new_corners.len && !removed_corners.len)
		return //Nothing to do, avoid wasting time.

	var/sunlight_mult = 0
	switch(sunlight)
		if(TRUE)
			sunlight_mult = 0.6
		if(SUNLIGHT_OVERHEAD)
			sunlight_mult = 1.0
	var/brightness = sun.our_brightness * sunlight_mult * SSlighting.sun_mult
	var/list/color = hex2rgb(sun.our_color)
	var/red = brightness * (color[1] / 255.0)
	var/green = brightness * (color[2] / 255.0)
	var/blue = brightness * (color[3] / 255.0)
	var/delta_r = red - effect_str_r
	var/delta_g = green - effect_str_g
	var/delta_b = blue - effect_str_b

	for(var/datum/lighting_corner/corner in affected)
		corner.update_lumcount(delta_r,delta_g,delta_b,from_sholder=TRUE)

	for(var/datum/lighting_corner/corner in new_corners)
		corner.update_lumcount(red,green,blue,from_sholder=TRUE)
		affected += corner

	for(var/datum/lighting_corner/corner in removed_corners)
		corner.update_lumcount(-effect_str_r,-effect_str_g,-effect_str_b,from_sholder=TRUE)

	if(!affected.len)
		effect_str_r = 0
		effect_str_g = 0
		effect_str_b = 0
		return

	effect_str_r = red
	effect_str_g = green
	effect_str_b = blue

/datum/sunlight_handler/proc/corner_sunlight_change(var/datum/lighting_corner/sender)
	if(only_sun_object)
		only_sun_object.sunlight_only = FALSE
		only_sun_object = null

	if(!(sender in only_sun))
		return

	sender.sunlight = SUNLIGHT_CURRENT

	sender.update_lumcount(effect_str_r,effect_str_g,effect_str_b,from_sholder=TRUE)
	only_sun -= sender
	affected += sender
