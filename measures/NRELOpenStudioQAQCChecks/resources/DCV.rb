class XcelEDAReportingandQAQC < OpenStudio::Ruleset::ReportingUserScript

  def dcv_check
    
    # Check for systems that should have DCV but don't (from 90.1-2007):
    # 6.4.3.9 	Ventilation Controls for High-Occupancy Areas. 
    # Demand control ventilation (DCV) is required for spaces larger than 500 ft2 and 
    # with a design occupancy for ventilation of greater than 40 people per 1000 ft2 of floor area 
    # and served by systems with one or more of the following:
    # a.		an air-side economizer,
    # b.		automatic modulating control of the outdoor air damper, or
    # c.		a design outdoor airflow greater than 3000 cfm.

    # TODO
    # incorporate building type into the range checking - ASHRAE Standard 100
    # how many hours did the @model run for? - make sure 8760 - get from html file
    
    check = CheckData.new
    check.name = "DCV Check"
    check.descr = "Check for zones that should have DCV per 90.1 but currently don't."
    
    @model.getThermalZones.each do |zone|
      
      # Skip zones not connected to an air loop
      next if not zone.airLoopHVAC.is_initialized
      
      # Get the zone area
      next if not zone.floorArea
      area_m2 = zone.floorArea
      area_ft2 = OpenStudio::convert(area_m2,"m^2","ft^2").get
      
      # Skip areas smaller than 500 ft2
      next if area_ft2 < 500
      
      density_or_oa_req_dcv = false
      
      # Get the area per occupant
      # DCV required if density more than 40 people / 1000 ft2
      area_per_occupant_m2 = zone.areaPerOccupant
      if not area_per_occupant_m2.is_initialized
        check.msgs << ['warn',"Could not find area per occupant for #{zone.name}."]
        next
      end
      area_per_occupant_m2 = area_per_occupant_m2.get
      area_per_occupant_ft2 = OpenStudio::convert(area_per_occupant_m2,"m^2","ft^2").get
      occupant_per_area_ft2 = 1/area_per_occupant_ft2
      occ_per_thousand_ft2 = occupant_per_area_ft2 * 1000
      if occ_per_thousand_ft2 > (40)
        check.msgs << ['info',"#{zone.name}' occ density of #{occ_per_thousand_ft2} people/1000ft2 is greater than 40 people/1000 ft2; requires DCV."]
        density_or_oa_req_dcv = true
      end

      # Get the total OA cfm
      # DCV required if design OA more than 3000 cfm
      if not zone.volumeFromOACalc.is_initialized
        check.msgs << ['warn',"Could not find volume for #{zone.name}."]
        next
      end
      volume_m3 = zone.volumeFromOACalc.get
      volume_ft3 = OpenStudio::convert(volume_m3,"m^3","ft^3").get   
      if not zone.averageOutdoorAirACH.is_initialized
        check.msgs << ['warn',"Could not find volume for #{zone.name}."]
        next
      end
      oa_ach = zone.averageOutdoorAirACH.get
      zone_oa_m3_per_hr = volume_m3 * oa_ach
      zone_oa_ft3_per_min = OpenStudio::convert(zone_oa_m3_per_hr,"m^3/hr","ft^3/min").get
      if zone_oa_ft3_per_min > 3000.0     
        check.msgs << ['info',"'#{zone.name}' design OA of #{zone_oa_ft3_per_min} cfm is greater than 3000 cfm; requires DCV."]
        density_or_oa_req_dcv = true
      end
      
      # Skip spaces that don't require DCV
      next if density_or_oa_req_dcv == false
 
      # This space requires DCV; check if already installed
      air_loop = zone.airLoopHVAC.get
      air_loop.supplyComponents.each do |sup_comp|
        if sup_comp.to_AirLoopHVACOutdoorAirSystem.is_initialized
          oa_sys = sup_comp.to_AirLoopHVACOutdoorAirSystem.get
          controller_oa = oa_sys.getControllerOutdoorAir
          controller_mv = controller_oa.controllerMechanicalVentilation
          # Warn if demand control is not enabled
          if controller_mv.demandControlledVentilation == false
            check.msgs << ['warn',"Zone '#{zone.name}' on Air Loop '#{air_loop.name}' should
                                    have DCV enabled per 90.1, but does not.  DCV is
                                    required because the zone has a high occupant density
                                    or OA flow rate. Without DCV, the HVAC systems will provide much more ventilation than 
                                    necessary during times when the space is lightly occupied.  This
                                    will typically result in unreasonably high heating and/or
                                    cooling energy consumption.  To turn on DCV, go to the 
                                    HVAC systems tab, find the Air Loop '#{air_loop.name}',
                                    go to the controls pane, and toggle DCV to 'On.'"]
          end
        end
      end
    end # Next zone

    
    return check
    
  end    
  
 end 