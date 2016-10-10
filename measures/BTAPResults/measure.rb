require 'erb'
require 'json'


# start the measure
class BTAPResults < OpenStudio::Ruleset::ReportingUserScript
  # define the name that a user will see, this method may be deprecated as
  # the display name in PAT comes from the name field in measure.xml
  def name
    'BTAP Results'
  end

  # human readable description
  def description
    'This measure creates BTAP result values used for NRCan analyses.'
  end

  # human readable description of modeling approach
  def modeler_description
    'Grabs data from OS model and sql database and keeps them in the '
  end



  # define the arguments that the user will input
  def arguments
    args = OpenStudio::Ruleset::OSArgumentVector.new
  end # end the arguments method



  # define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)

    # get sql, model, and web assets
    setup = OsLib_Reporting.setup(runner)
    unless setup
      return false
    end
    model = setup[:model]
    # workspace = setup[:workspace]
    sql_file = setup[:sqlFile]
    web_asset_path = setup[:web_asset_path]

    # reporting final condition
    runner.registerInitialCondition('Gathering data from EnergyPlus SQL file and OSM model.')

    #link sql output
          model.setSqlFile(sql_file)

          @current_building = model.building.get
          @current_facility = model.getFacility
          @weather_object = model.getWeatherFile

          #Create hash of results.
          @annual_results_array = Array.new()


          #Weather file
          @annual_results_array.push( [ @weather_object.city, "City","-"])
          @annual_results_array.push( [ @weather_object.stateProvinceRegion, "Province","-"])
          @annual_results_array.push( [ @weather_object.country, "Country","-"])
          @annual_results_array.push( [ @weather_object.dataSource, "Data Source","-"])
          @annual_results_array.push( [ @weather_object.wMONumber, "wMONumber","-"])
          @annual_results_array.push( [ @weather_object.latitude, "Latitude","-"])
          @annual_results_array.push( [ @weather_object.longitude, "Longitude","-"])

          hdd = BTAP::Environment::WeatherFile.new( @weather_object.path.get.to_s ).hdd18
          cdd = BTAP::Environment::WeatherFile.new( @weather_object.path.get.to_s ).cdd18
          @annual_results_array.push( [ hdd, "Heating Degree Days","deg*Day"])
          @annual_results_array.push( [ cdd, "Cooling Degree Days","deg*Day"])
          @annual_results_array.push( [ BTAP::Compliance::NECB2011::get_climate_zone_name(hdd), "NECB Climate Zone",""])

          conditionedFloorArea = @current_building.conditionedFloorArea()#m2
          exteriorSurface_area = @current_building.exteriorSurfaceArea() #m2
          building_air_volume = @current_building.airVolume() #m3
          
          @annual_results_array.push( [ BTAP::Compliance::NECB2011::get_climate_zone_name(hdd), "NECB Climate Zone",""])
          @annual_results_array.push( [ BTAP::Compliance::NECB2011::get_climate_zone_name(hdd), "NECB Climate Zone",""])
          @annual_results_array.push( [ BTAP::Compliance::NECB2011::get_climate_zone_name(hdd), "NECB Climate Zone",""])


          #Average loads
          @annual_results_array.push( [ conditionedFloorArea,"conditionedFloorArea","M2"])
          @annual_results_array.push( [ exteriorSurface_area,"exteriorSurface_area","M2"])
          @annual_results_array.push( [ building_air_volume,"building_air_volume","M3"])



          #unmet hours
          @annual_results_array.push( [ @current_facility.hoursHeatingSetpointNotMet(),"Unmet Hours Heating ", "Hours"])
          @annual_results_array.push( [ @current_facility.hoursCoolingSetpointNotMet(),"Unmet Hours Cooling ", "Hours"])

          #cost information
          @annual_results_array.push( [ @current_facility.annualTotalCostPerNetConditionedBldgArea(OpenStudio::FuelType.new("NaturalGas")), "Natural Gas Total Cost Intensity", "$/M2"])
          @annual_results_array.push( [ @current_facility.economicsVirtualRateGas(), "NaturalGas Virtual Rate", "$/GJ"])
          @annual_results_array.push( [ @current_facility.annualTotalCostPerNetConditionedBldgArea(OpenStudio::FuelType.new("Electricity")), "Electricity Total Cost Intensity", "$/M2"])
          @annual_results_array.push( [ @current_facility.economicsVirtualRateElec(), "Electricity  Virtual Rate", "$/GJ"])
          @annual_results_array.push( [ @current_facility.economicsVirtualRateCombined(), "Elec-Gas-Combined Virtual Rate", "$/GJ"])
          @annual_results_array.push( [ @current_facility.annualTotalCostPerNetConditionedBldgArea(OpenStudio::FuelType.new("DistrictCooling")), "DistrictCooling Total Cost Intensity", "$/M2"])
          @annual_results_array.push( [ @current_facility.annualTotalCostPerNetConditionedBldgArea(OpenStudio::FuelType.new("DistrictHeating")), "DistrictHeating Total Cost Intensity", "$/M2"])
          @annual_results_array.push( [ @current_facility.economicsSPB(), "economics Simple Pay Back", "Years"])
          @annual_results_array.push( [ @current_facility.economicsIRR(), "economics Internal Rate of Return", "%"])

          # @annual_results_array.each {|result| puts "#{result[0]}, #{result[1]}, #{result[2]}, #{basename}" }
          #Determine weighted area average conductances
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
          @annual_results_array.push( [ outdoor_walls_average_conductance ,"outdoor_walls_average_conductance", "?"])
          @annual_results_array.push( [ outdoor_roofs_average_conductance ,"outdoor_roofs_average_conductance", "?"])
          @annual_results_array.push( [ outdoor_floors_average_conductance ,"outdoor_floors_average_conductance", "?"])
          @annual_results_array.push( [ windows_average_conductance ,"outdoor_windows_average_conductance", "?"])
          @annual_results_array.push( [ doors_average_conductance ,"outdoor_doors_average_conductance", "?"])
          @annual_results_array.push( [ overhead_doors_average_conductance ,"outdoor_overhead_doors_average_conductance", "?"])
          @annual_results_array.push( [ skylights_average_conductance ,"skylights_average_conductance", "?"])
          @annual_results_array.push( [ BTAP::Geometry::get_fwdr(model) * 100.0, "Fenestration To Wall Ratio", "%"])
          @annual_results_array.push( [ BTAP::Geometry::get_srr(model)* 100.0, "Skylight to Roof Ratio", "%"])

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

          @annual_results_array.push( [ electric_peak ,"Peak Electricity", "W"])
          @annual_results_array.push( [ natural_gas_peak ,"Peak Gas", "W"])

          #Get End Uses by fuel type.

          def end_use_intensity(model,use_type,fuel_type)
            fuel_name = fuel_type[0]
            fuel_units = fuel_type[1]
            value = model.sqlFile().get().execAndReturnFirstDouble("SELECT Value FROM tabulardatawithstrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' AND ReportForString='Entire Facility' AND TableName='End Uses' AND RowName='#{use_type}' AND ColumnName='#{fuel_name}' AND Units='#{fuel_units}'")
            if value.empty?
              value = 0.0
            else
              value = value.get
            end
            @annual_results_array.push( [ value, "#{fuel_name}-#{use_type}", fuel_units])
            @annual_results_array.push( [ value / @current_building.floorArea() , "#{fuel_name}-#{use_type}  Intensity", "#{fuel_units}/m2"] )
          end
          #Heating Energy
          end_use_intensity( model,"Heating",['Electricity', 'GJ'] )
          end_use_intensity(model,"Heating",['Natural Gas', 'GJ'] )
          end_use_intensity(model,"Heating",['District Heating', 'GJ'] )
          #Cooling Energy
          end_use_intensity(model,'Cooling',['Electricity', 'GJ'] )
          end_use_intensity(model,"Cooling",['District Cooling', 'GJ'] )
          #Lighting Energy
          end_use_intensity(model,'Interior Lighting',['Electricity', 'GJ'] )
          end_use_intensity(model,'Exterior Lighting',['Electricity', 'GJ'] )
          #Equipment Energy
          end_use_intensity(model,'Interior Equipment',['Electricity', 'GJ'] )
          end_use_intensity(model,'Exterior Equipment',['Electricity', 'GJ'] )
          end_use_intensity(model,'Interior Equipment',['Natural Gas', 'GJ'] )
          end_use_intensity(model,'Exterior Equipment',['Natural Gas', 'GJ'] )
          #Fans/Pumps
          end_use_intensity(model,'Fans',['Electricity', 'GJ'] )
          end_use_intensity(model,'Pumps',['Electricity', 'GJ'] )
          #Heat Rejection
          end_use_intensity(model,'Heat Rejection',['Electricity', 'GJ'] )
          end_use_intensity(model,'Heat Rejection',['Natural Gas', 'GJ'] )
          #Humidification
          end_use_intensity(model,'Humidification',['Electricity', 'GJ'] )
          end_use_intensity(model,'Humidification',['Natural Gas', 'GJ'] )
          #Heat Recovery
          end_use_intensity(model,'Heat Recovery',['Electricity', 'GJ'] )
          end_use_intensity(model,'Heat Recovery',['Natural Gas', 'GJ'] )
          #Water Systems
          end_use_intensity(model,'Water Systems',['Electricity', 'GJ'] )
          end_use_intensity(model,'Water Systems',['Natural Gas', 'GJ'] )
          #Refrigeration
          end_use_intensity(model,'Refrigeration',['Electricity', 'GJ'] )
          #Generators
          end_use_intensity(model,'Generators',['Electricity', 'GJ'] )
          end_use_intensity(model,'Generators',['Natural Gas', 'GJ'] )


    # closing the sql file
    sql_file.close

@annual_results_array.each do |result|
#runner.registerValue(result[1],result[0],result[2])
end

    # reporting final condition
    runner.registerFinalCondition("Saved BTAP results to runner.")

    true
  end # end the run method
end # end the measure

# this allows the measure to be use by the application
BTAPResults.new.registerWithApplication