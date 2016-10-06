class XcelEDAReportingandQAQC < OpenStudio::Ruleset::ReportingUserScript

  def eui_check

    # Checks the EUI for the whole building

    # TODO
    # incorporate building type into the range checking - ASHRAE Standard 100
    # how many hours did the @model run for? - make sure 8760 - get from html file
    
    check = CheckData.new
    check.name = "EUI Check"
    check.descr = "Check that the EUI of the building is reasonable."

    building = @model.getBuilding
    
    # Make sure all required data are available
    if @sql.totalSiteEnergy.empty?
      check.msgs << ['info',"Site energy data unavailable; check not run."]
      return check
    end
    
    total_site_energy_kBtu = OpenStudio::convert(@sql.totalSiteEnergy.get, "GJ", "kBtu").get
    if total_site_energy_kBtu == 0
      check.msgs << ['warn',"Model site energy use = 0; likely a problem with the model."]
      check.msgs << ['cause', "Model may be set to only run design days, not full year.  On the 'Simulation Settings' tab, check the 'Run Simulation For' switches."]
      check.msgs << ['cause',<< "Model may not have any loads or HVAC.  Check for loads in spaces in the tree on the 'Facility' tab."]
    end
  
    floor_area_ft2 = OpenStudio::convert(building.floorArea, "m^2", "ft^2").get
    if floor_area_ft2 == 0
      check.msgs << ['warn',"The building has 0 floor area."]
      check.msgs << ['cause',"All spaces in model may be set to 'Not Part of Conditioned Floor Area'.  In the SketchUp plugin, click on a space, and in the inpector, check the 'Part of Conditioned Floor Area' setting."]
    end
    
    site_EUI = total_site_energy_kBtu / floor_area_ft2
    
    if site_EUI > 200
      check.msgs << ['warn',"Site EUI of #{site_EUI} looks high.  A hospital or lab (high energy buildings) are around 200 kBtu/ft^2"
    end
    
    if site_EUI < 30
      check.msgs << ['warn',"Site EUI of #{site_EUI} looks low.  A high efficiency office building is around 50 kBtu/ft^2"]
    end
    
 
    return check
    
  end    
  
 end 