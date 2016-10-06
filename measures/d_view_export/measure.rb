# see the URL below for information on how to write OpenStudio measures
# http://openstudio.nrel.gov/openstudio-measure-writing-guide

require 'erb'
require 'csv'

#start the measure
class BTAPReports < OpenStudio::Ruleset::ReportingUserScript

  # human readable name
  def name
    return "BTAP Reports"
  end

  # human readable description
  def description
    return "Collects all Information required for BTAP runs."
  end

  # human readable description of modeling approach
  def modeler_description
    return "Collects all Information required for BTAP runs."
  end

  # define the arguments that the user will input
  def arguments()
    args = OpenStudio::Ruleset::OSArgumentVector.new
    return args
  end
  
  # return a vector of IdfObject's to request EnergyPlus objects needed by the run method
  def energyPlusOutputRequests(runner, user_arguments)
    super(runner, user_arguments)
    return result = OpenStudio::IdfObjectVector.new
  end
  
  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # use the built-in error checking 
    if !runner.validateUserArguments(arguments(), user_arguments)
      return false
    end
    
    # get the last model and sql file
    model = runner.lastOpenStudioModel
    if model.empty?
      runner.registerError("Cannot find last model.")
      return false
    end
    model = model.get

    sql = runner.lastEnergyPlusSqlFile
    if sql.empty?
      runner.registerError("Cannot find last sql file.")
      return false
    end
    sql = sql.get
    model.setSqlFile(sql)

   
outdoor_surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(model.getSurfaces(), "Outdoors")
      current_building = model.building
      current_facility = model.getFacility
      weather_object = model.getWeatherFile

      #Create hash of results.
      annual_results_array = Array.new()

      #Weather file data
      annual_results_array.push( [ weather_object.city, "City","-"])
      annual_results_array.push( [ weather_object.stateProvinceRegion, "Region","-"])
      annual_results_array.push( [ weather_object.country, "Country","-"])
      annual_results_array.push( [ weather_object.dataSource, "Data Source","-"])
      annual_results_array.push( [ weather_object.wMONumber, "wMONumber","-"])
      annual_results_array.push( [ weather_object.latitude, "Latitude","-"])
      annual_results_array.push( [ weather_object.longitude, "Longitude","-"])
      hdd = BTAP::Environment::WeatherFile.new( weather_object.path.get.to_s ).hdd18
      cdd = BTAP::Environment::WeatherFile.new( weather_object.path.get.to_s ).cdd18
      annual_results_array.push( [ hdd, "Heating Degree Days","deg*Day"])
      annual_results_array.push( [ cdd, "Cooling Degree Days","deg*Day"])
      annual_results_array.push( [ BTAP::Compliance::NECB2011::get_climate_zone_name(hdd), "NECB Climate Zone",""])

      
     
      conditionedFloorArea = current_building.conditionedFloorArea()#m2
      exteriorSurface_area = current_building.exteriorSurfaceArea() #m2
      air_volume = current_building.airVolume() #m3

      #Average loads
      annual_results_array.push( [ current_building.peoplePerFloorArea(),"Number of People per Area","Persons/M2"])       
      annual_results_array.push( [ current_building.lightingPowerPerFloorArea(),"Lighting Power Density","W/M2"])
      annual_results_array.push( [ current_building.electricEquipmentPowerPerFloorArea(),"Electric Equipment Power Density","W/M2"])
      annual_results_array.push( [ current_building.gasEquipmentPowerPerFloorArea(),"Gas Equipment Power Density","W/M2"])        
        
      #Site / Source Energy Intensity
      annual_results_array.push( [ current_facility.totalSiteEnergy() / conditionedFloorArea , "Total Site Energy Intensity", "GJ/M2"])
      annual_results_array.push( [ current_facility.netSiteEnergy()  / conditionedFloorArea , "Net Site Energy Intensity", "GJ/M2"])
      annual_results_array.push( [ current_facility.totalSourceEnergy() / conditionedFloorArea , "Total Source Energy Intensity", "GJ/M2"])
      annual_results_array.push( [ current_facility.netSourceEnergy() / conditionedFloorArea, "Net Source Energy Intensity", "GJ/M2"])

      #unmet hours
      annual_results_array.push( [ current_facility.hoursHeatingSetpointNotMet(),"Unmet Hours Heating ", "Hours"])
      annual_results_array.push( [ current_facility.hoursCoolingSetpointNotMet(),"Unmet Hours Cooling ", "Hours"])

      #cost information
      annual_results_array.push( [ current_facility.annualTotalCostPerNetConditionedBldgArea(OpenStudio::FuelType.new("NaturalGas")), "Natural Gas Total Cost Intensity", "$/M2"])
      annual_results_array.push( [ current_facility.economicsVirtualRateGas(), "NaturalGas Virtual Rate", "$/GJ"])
      annual_results_array.push( [ current_facility.annualTotalCostPerNetConditionedBldgArea(OpenStudio::FuelType.new("Electricity")), "Electricity Total Cost Intensity", "$/M2"])
      annual_results_array.push( [ current_facility.economicsVirtualRateElec(), "Electricity  Virtual Rate", "$/GJ"])
      annual_results_array.push( [ current_facility.economicsVirtualRateCombined(), "Elec-Gas-Combined Virtual Rate", "$/GJ"])
      annual_results_array.push( [ current_facility.annualTotalCostPerNetConditionedBldgArea(OpenStudio::FuelType.new("DistrictCooling")), "DistrictCooling Total Cost Intensity", "$/M2"])
      annual_results_array.push( [ current_facility.annualTotalCostPerNetConditionedBldgArea(OpenStudio::FuelType.new("DistrictHeating")), "DistrictHeating Total Cost Intensity", "$/M2"])
      annual_results_array.push( [ current_facility.annualTotalUtilityCost() / conditionedFloorArea , "Total Utility Cost Intensity", "$"])
      annual_results_array.push( [ current_facility.economicsCapitalCost() / conditionedFloorArea , "Capitol Costs Intensity", "$/M2"])
      annual_results_array.push( [ current_facility.economicsSPB(), "economics Simple Pay Back", "Years"])
      annual_results_array.push( [ current_facility.economicsIRR(), "economics Internal Rate of Return", "%"])

      #Annual_results_array.each {|result| puts "#{result[0]}, #{result[1]}, #{result[2]}, #{basename}" }
      # Determine weighted area average conductances
      outdoor_surfaces = BTAP::Geometry::Surfaces::filter_by_boundary_condition(model.getSurfaces(), "Outdoors")
      outdoor_walls = BTAP::Geometry::Surfaces::filter_by_surface_types(outdoor_surfaces, "Wall")
      outdoor_roofs = BTAP::Geometry::Surfaces::filter_by_surface_types(outdoor_surfaces, "RoofCeiling")
      outdoor_floors = BTAP::Geometry::Surfaces::filter_by_surface_types(outdoor_surfaces, "Floor")
      outdoor_subsurfaces = BTAP::Geometry::Surfaces::get_subsurfaces_from_surfaces(outdoor_surfaces)
      windows = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(outdoor_subsurfaces, ["FixedWindow" , "OperableWindow" ])
      skylights = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(outdoor_subsurfaces, ["Skylight", "TubularDaylightDiffuser","TubularDaylightDome" ])
      doors = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(outdoor_subsurfaces, ["Door" , "GlassDoor" ])
      overhead_doors = BTAP::Geometry::Surfaces::filter_subsurfaces_by_types(outdoor_subsurfaces, ["OverheadDoor" ])
      outdoor_walls_average_conductance = BTAP::Geometry::Surfaces::get_weighted_average_surface_conductance(outdoor_walls)
      outdoor_roofs_average_conductance = BTAP::Geometry::Surfaces::get_weighted_average_surface_conductance(outdoor_roofs)
      outdoor_floors_average_conductance = BTAP::Geometry::Surfaces::get_weighted_average_surface_conductance(outdoor_floors)
      windows_average_conductance = BTAP::Geometry::Surfaces::get_weighted_average_surface_conductance(windows)
      skylights_average_conductance = BTAP::Geometry::Surfaces::get_weighted_average_surface_conductance(skylights)
      doors_average_conductance = BTAP::Geometry::Surfaces::get_weighted_average_surface_conductance(doors)
      overhead_doors_average_conductance = BTAP::Geometry::Surfaces::get_weighted_average_surface_conductance(overhead_doors)
      #Store Values
      annual_results_array.push( [ outdoor_walls_average_conductance ,"outdoor_walls_average_conductance", "?"])
      annual_results_array.push( [ outdoor_roofs_average_conductance ,"outdoor_roofs_average_conductance", "?"])
      annual_results_array.push( [ outdoor_floors_average_conductance ,"outdoor_floors_average_conductance", "?"])
      annual_results_array.push( [ windows_average_conductance ,"outdoor_windows_average_conductance", "?"])
      annual_results_array.push( [ doors_average_conductance ,"outdoor_doors_average_conductance", "?"])
      annual_results_array.push( [ overhead_doors_average_conductance ,"outdoor_overhead_doors_average_conductance", "?"])
      annual_results_array.push( [ skylights_average_conductance ,"skylights_average_conductance", "?"])
      annual_results_array.push( [ BTAP::Geometry::get_fwdr(model) * 100.0, "Fenestration To Wall Ratio", "%"])
      annual_results_array.push( [ BTAP::Geometry::get_srr(model)* 100.0, "Skylight to Roof Ratio", "%"])

      #Get peak watts for gas and elec
      electric_peak  = model.sqlFile().get().execAndReturnFirstDouble("SELECT Value FROM tabulardatawithstrings WHERE ReportName='EnergyMeters'" +
          " AND ReportForString='Entire Facility' AND TableName='Annual and Peak Values - Electricity' AND RowName='Electricity:Facility'" +
          " AND ColumnName='Electricity Maximum Value' AND Units='W'")
      if electric_peak.empty?
        electric_peak = 0.0
      end

      natural_gas_peak = model.sqlFile().get().execAndReturnFirstDouble("SELECT Value FROM tabulardatawithstrings WHERE ReportName='EnergyMeters'" +
          " AND ReportForString='Entire Facility' AND TableName='Annual and Peak Values - Gas' AND RowName='Gas:Facility'" +
          " AND ColumnName='Gas Maximum Value' AND Units='W'")
      if natural_gas_peak.empty?
        natural_gas_peak = 0.0
      end

      annual_results_array.push( [ electric_peak ,"Peak Electricity", "W"])
      annual_results_array.push( [ natural_gas_peak ,"Peak Gas", "W"])

      #Get End Uses by fuel type.
  
      def end_use_intensity(use_type,fuel_type)
        fuel_name = fuel_type[0]
        fuel_units = fuel_type[1]
        value = model.sqlFile().get().execAndReturnFirstDouble("SELECT Value FROM tabulardatawithstrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' AND ReportForString='Entire Facility' AND TableName='End Uses' AND RowName='#{use_type}' AND ColumnName='#{fuel_name}' AND Units='#{fuel_units}'")
        if value.empty?
          value = 0.0
        else
          value = value.get
        end
        annual_results_array.push( [ value, "#{fuel_name}-#{use_type}", fuel_units])
        annual_results_array.push( [ value / current_building.floorArea() , "#{fuel_name}-#{use_type}  Intensity", "#{fuel_units}/m2"] )
      end
      #Heating Energy
      end_use_intensity("Heating",['Electricity', 'GJ'] )
      end_use_intensity("Heating",['Natural Gas', 'GJ'] )
      end_use_intensity("Heating",['District Heating', 'GJ'] )
      #Cooling Energy
      end_use_intensity('Cooling',['Electricity', 'GJ'] )
      end_use_intensity("Cooling",['District Cooling', 'GJ'] )
      #Lighting Energy
      end_use_intensity('Interior Lighting',['Electricity', 'GJ'] )
      end_use_intensity('Exterior Lighting',['Electricity', 'GJ'] )
      #Equipment Energy
      end_use_intensity('Interior Equipment',['Electricity', 'GJ'] )
      end_use_intensity('Exterior Equipment',['Electricity', 'GJ'] )
      end_use_intensity('Interior Equipment',['Natural Gas', 'GJ'] )
      end_use_intensity('Exterior Equipment',['Natural Gas', 'GJ'] )
      #Fans/Pumps
      end_use_intensity('Fans',['Electricity', 'GJ'] )
      end_use_intensity('Pumps',['Electricity', 'GJ'] )
      #Heat Rejection
      end_use_intensity('Heat Rejection',['Electricity', 'GJ'] )
      end_use_intensity('Heat Rejection',['Natural Gas', 'GJ'] )
      #Humidification
      end_use_intensity('Humidification',['Electricity', 'GJ'] )
      end_use_intensity('Humidification',['Natural Gas', 'GJ'] )
      #Heat Recovery
      end_use_intensity('Heat Recovery',['Electricity', 'GJ'] )
      end_use_intensity('Heat Recovery',['Natural Gas', 'GJ'] )
      #Water Systems	
      end_use_intensity('Water Systems',['Electricity', 'GJ'] )
      end_use_intensity('Water Systems',['Natural Gas', 'GJ'] )
      #Refrigeration	
      end_use_intensity('Refrigeration',['Electricity', 'GJ'] )
      #Generators	
      end_use_intensity('Generators',['Electricity', 'GJ'] )
      end_use_intensity('Generators',['Natural Gas', 'GJ'] )

####    Hourly Data



    # Get the weather file run period (as opposed to design day run period)
    ann_env_pd = nil
    sql.availableEnvPeriods.each do |env_pd|
      env_type = sql.environmentType(env_pd)
      if env_type.is_initialized
        if env_type.get == OpenStudio::EnvironmentType.new("WeatherRunPeriod")
          ann_env_pd = env_pd
        end
      end
    end

    if ann_env_pd == false
      runner.registerError("Can't find a weather runperiod, make sure you ran an annual simulation, not just the design days.")
      return false
    end
    
    # Get the timestep as fraction of an hour
    ts_frac = 1.0/4.0 # E+ default
    sim_ctrl = model.getSimulationControl
    step = sim_ctrl.timestep
    if step.is_initialized
      step = step.get
      steps_per_hr = step.numberOfTimestepsPerHour
      ts_frac = 1.0/steps_per_hr.to_f
    end
    ts_frac = ts_frac.round(5)
    #runner.registerInfo("The timestep is #{ts_frac} of an hour.")

    ts_names = sql.availableTimeSeries
    freqs = sql.availableReportingFrequencies(ann_env_pd)
    #sql.timeSeries(ann_env_pd, freq, var_name, kv)
    checked = []
    valid = []
    puts "#{ts_names} ts_names"
    puts "#{freqs} freqs"
    ts_names.each do |ts_name|
      freqs.each do |freq|
        var_names = sql.availableVariableNames(ann_env_pd, freq)
        var_names.each do |var_name|
        puts "#{var_name} var_name"
          key_vals = sql.availableKeyValues(ann_env_pd, freq, var_name)
          puts "#{key_vals} key_vals"
          key_vals.each do |kv|
            combo = [ann_env_pd, freq, var_name, kv]
            next if checked.include?(combo)
            checked << combo
            ts = sql.timeSeries(ann_env_pd, freq, var_name, kv)
            if ts.is_initialized
              valid << combo
            end
          end
        end
      end
    end
    
    # Report out the number of series found
    runner.registerInitialCondition("Found #{valid.size} timeseries outputs.")
    
    # Determine the number of hours simulated
    hrs_sim = sql.hoursSimulated
    if hrs_sim.is_initialized
      hrs_sim = hrs_sim.get
    else
      runner.registerWarning("Could not determine number of hours simulated, assuming 8760")
      hrs_sim = 8760
    end
    
    # Determine the maximum number of entries, which is minutely
    max_vals = (hrs_sim * 60).round

    # Create a DView csv for each frequency
    # For details on the file format, see the reference here:
    # https://beopt.nrel.gov/sites/beopt.nrel.gov/files/exes/DataFileTemplate.pdf
     
    # Create an array of rows, one for each series
    minutely_series = []
    timestep_series = []
    hourly_series = []
    valid.each do |ann_env_pd, freq, var_name, kv|

      # For now, skip Runperiod, Monthly, and Daily data
      next unless freq == 'HVAC System Timestep' ||
                  freq == 'Zone Timestep' ||
                  freq == 'Timestep' ||
                  freq == 'Hourly'
      row = []
      
      # Series name
      name = nil
      if kv == ''
        name = "#{var_name.gsub('|','_')}"
      else
        name = "#{var_name.gsub('|','_')}|#{kv.gsub('|','_')}"
      end
      row << name
      
      # Indicated the start time from
      # Midnight Jan 1 of first datapoint.
      row << 0.0
      
      # Series frequency in hrs
      ts_hr = nil
      case freq
      when 'HVAC System Timestep'
        ts_hr = 1.0 / 60.0 # Convert from non-uniform to minutely
      when 'Timestep', 'Zone Timestep'
        ts_hr = ts_frac
      when 'Hourly'
        ts_hr = 1.0
      when 'Daily'
        ts_hr = 24.0
      when 'Monthly'
        ts_hr = 24.0 * 30 # Even months
      when 'Runperiod'
        ts_hr = 24.0 * 365 # Assume whole year run
      end
      row << ts_hr.round(8)
      
      # Get the values
      ts = sql.timeSeries(ann_env_pd, freq, var_name, kv)
      puts "#{ts.get.dateTimes.first.to_s} ts"
      if ts.empty?
        runner.registerWarning("No data found for #{freq} #{var_name} #{kv}.")
        next
      else
        ts = ts.get
      end
      times = ts.dateTimes
      vals = ts.values
      units = ts.units
      new_units = units

      # For HVAC System Timestep data, convert from E+ 
      # non-uniform timesteps to minutely with blanks
      # where there are no entries.
      if freq == 'HVAC System Timestep'
        next unless kv.include?('VAV_POD_1')

        # Loop through each of the non-uniformly
        # reported timesteps.
        start_min = 0
        first_timestep = times[0]
        minutely_vals = []
        for i in 1..(times.size - 1)
          reported_time = times[i]
          
          # At each minute, report a value if one
          # exists and a blank if none exists.
          for min in start_min..525600
            minute_ts = OpenStudio::Time.new(0, 0, min, 0) # d, hr, min, s
            minute_time = first_timestep + minute_ts
            if minute_time == reported_time
              # There was a value for this minute,
              # report out this value and skip
              # to the next reported timestep
              start_min = min + 1
              minutely_vals << vals[i]
              #puts "#{minute_time} = #{vals[i]}"
              break
            elsif minute_time < reported_time
              # There wasn't a value for this minute,
              # report out a blank row
              minutely_vals << nil
              #puts "#{minute_time} = "
            else 
              # minute_time > reported_time
              # This scenario shouldn't happen
              runner.registerError("Somehow a timestep was skipped when converting from HVAC System Timestep to uniform minutely.  Results will not look correct.")
            end
          end
          
        end
        
        # Replace the original values
        # with the new minutely values
        vals = minutely_vals
        
      end

      # Convert the values to a normal array
      data = Array.new(max_vals)
      for i in 0..(vals.size - 1)
        v = vals[i]
        
        # Skip nil values
        next if v.nil?
        
        # Convert to IP units
        # for some specific cases
        case units
        when 'C'
          new_units = 'F'
          v_before = v
          v = OpenStudio.convert(v,units,new_units).get
        when 'm3/s'
          new_units = nil
          if var_name.include?('Pump') || var_name.include?('Fluid')
            new_units = 'gal/min'
          else
            new_units = 'cfm'
          end
          v = OpenStudio.convert(v,units,new_units).get
        when 'kg/s', 'Kg/s'
          new_units = nil
          conversion_factor = nil
          if var_name.include?('Pump') || var_name.include?('Fluid')
            new_units = 'gpm water'
            conversion_factor = 0.2642 * 60 # 1 kg water = 0.2642 gal
          else
            new_units = 'cfm air'
            conversion_factor = 27.69 * 60 # 1 kg air = 27.69 ft3
          end
          v = v * conversion_factor
        
        end
        data[i] = v
        
      end

      # Append the units and values
      row << new_units
      row += data
      
      # Add the series
      case freq
      when 'HVAC System Timestep'
        minutely_series << row
      when 'Timestep', 'Zone Timestep'
        timestep_series << row
      when 'Hourly'
        hourly_series << row
      end
      
    end

    # Export hourly and timestep data to CSV
    [minutely_series, timestep_series, hourly_series].each_with_index do |series, i|
      # Transpose the series and write to CSV
      rows = series.transpose
      
      # Don't export blank files
      next if rows.size == 0
      
      # Write the rows out to CSV
      file_name = nil
      case i
      when 0
        file_name = 'data_minute.dview'
      when 1
        file_name = 'data_timestep.dview'
      when 2
        file_name = 'data_hourly.dview'
      end
      
      csv_path = "#{File.dirname(__FILE__)}/#{file_name}"
      CSV.open(csv_path, "wb") do |csv|
        # Write the header row
        csv << ["wxDVFileHeaderVer.1"]
        # Write each row
        rows.each do |row|
          csv << row #+ [nil]
        end
      end  
      runner.registerInfo("DView CSV file saved to <a href='file:///#{csv_path}'>#{file_name}</a>.")
    end

    runner.registerInfo("DView can open more than one file at a time, so if you want to graph minute, timestep, and hourly data on the same graph, open the files sequentially in the same DView instance.")
    
    # close the sql file
    sql.close

    return true
 
  end

end

# register the measure to be used by the application
BTAPReports.new.registerWithApplication
