require 'erb'
require 'json'
require 'zlib'
require 'base64'


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


  def store_data(runner, value, name, units)
    begin
    name = name.to_s.squish.downcase.tr(" ","_")
    runner.registerValue(name.to_s,value.to_s)

    rescue
      runner.registerError(" Error is RegisterValue for these arguments #{name}, value:#{value}, units:#{units}")
    end
  end

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
    model.setSqlFile( sql_file )

    @current_building = model.building.get
    @current_facility = model.getFacility
    @weather_object = model.getWeatherFile
    hdd = BTAP::Environment::WeatherFile.new( @weather_object.path.get.to_s ).hdd18
    cdd = BTAP::Environment::WeatherFile.new( @weather_object.path.get.to_s ).cdd18
    
    #Determine weighted area average conductances
    conditionedFloorArea = @current_building.conditionedFloorArea()#m2
    exteriorSurface_area = @current_building.exteriorSurfaceArea() #m2
    building_air_volume = @current_building.airVolume() #m3
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

    #Compress model and store in base64 format
    store_data(runner, Base64.strict_encode64( Zlib::Deflate.deflate(model.to_s) ), "zipped_model_osm","-")

    #Weather file
    store_data(runner,  @weather_object.city, "geo_City","-")
    store_data(runner,  @weather_object.stateProvinceRegion, "geo_province","-")
    store_data(runner,  @weather_object.country, "geo_Country","-")
    store_data(runner,  @weather_object.dataSource, "geo_Data Source","-")
    store_data(runner,  @weather_object.wMONumber, "geo_wMONumber","-")
    store_data(runner,  @weather_object.latitude, "geo_latitude","-")
    store_data(runner,  @weather_object.longitude, "geo_longitude","-")
    store_data(runner,  hdd, "geo_Heating Degree Days","deg*Day")
    store_data(runner,  cdd, "geo_Cooling Degree Days","deg*Day")
    store_data(runner,  BTAP::Compliance::NECB2011::get_climate_zone_name(hdd), "env_NECB Climate Zone","")



    #unmet hours
    store_data(runner,  @current_facility.hoursHeatingSetpointNotMet(),"qaqc_unmet_hours_heating ", "Hours")
    store_data(runner,  @current_facility.hoursCoolingSetpointNotMet(),"qaqc_unmet_hours_cooling ", "Hours")

    #cost information
    store_data(runner,  @current_facility.annualTotalCostPerNetConditionedBldgArea(OpenStudio::FuelType.new("NaturalGas")), "econ_Natural Gas Total Cost Intensity", "$/M2")
    store_data(runner,  @current_facility.economicsVirtualRateGas(), "econ_NaturalGas Virtual Rate", "$/GJ")
    store_data(runner,  @current_facility.annualTotalCostPerNetConditionedBldgArea(OpenStudio::FuelType.new("Electricity")), "econ_Electricity Total Cost Intensity", "$/M2")
    store_data(runner,  @current_facility.economicsVirtualRateElec(), "econ_Electricity  Virtual Rate", "$/GJ")
    store_data(runner,  @current_facility.economicsVirtualRateCombined(), "econ_Elec-Gas-Combined Virtual Rate", "$/GJ")
    store_data(runner,  @current_facility.annualTotalCostPerNetConditionedBldgArea(OpenStudio::FuelType.new("DistrictCooling")), "econ_DistrictCooling Total Cost Intensity", "$/M2")
    store_data(runner,  @current_facility.annualTotalCostPerNetConditionedBldgArea(OpenStudio::FuelType.new("DistrictHeating")), "econ_DistrictHeating Total Cost Intensity", "$/M2")
    store_data(runner,  @current_facility.annualTotalUtilityCost(), "econ_Total Utility Cost", "$")
    #store_data(runner,  @current_facility.annualTotalUtilityCost() / conditionedFloorArea , "Total Utility Cost Intensity", "$/M2")



    #Store Values
    store_data(runner,  conditionedFloorArea,"envelope_conditioned_floor_area","M2")
    store_data(runner,  exteriorSurface_area,"envelope_exterior_Surface_area","M2")
    store_data(runner,  building_air_volume,"envelope_building_volume","M3")
    store_data(runner,  outdoor_walls_average_conductance ,"envelope_outdoor_walls_average_conductance", "?")
    store_data(runner,  outdoor_roofs_average_conductance ,"envelope_outdoor_roofs_average_conductance", "?")
    store_data(runner,  outdoor_floors_average_conductance ,"envelope_outdoor_floors_average_conductance", "?")
    store_data(runner,  windows_average_conductance ,"envelope_outdoor_windows_average_conductance", "?")
    store_data(runner,  doors_average_conductance ,"envelope_outdoor_doors_average_conductance", "?")
    store_data(runner,  overhead_doors_average_conductance ,"envelope_outdoor_overhead_doors_average_conductance", "?")
    store_data(runner,  skylights_average_conductance ,"envelope_skylights_average_conductance", "?")
    store_data(runner,  BTAP::Geometry::get_fwdr(model) * 100.0, "envelope_fdwr", "%")
    store_data(runner,  BTAP::Geometry::get_srr(model)* 100.0, "envelope_srr", "%")

    #store peak watts for gas and elec
    store_data(runner,  electric_peak ,"Peak Electricity", "W")
    store_data(runner,  natural_gas_peak ,"Peak Natural Gas", "W")

    #Get End Uses by fuel type.

     fuels = [ 
       ['Electricity', 'GJ'], 	
       ['Natural Gas', 'GJ'] ,	
       ['Additional Fuel', 'GJ'],
       ['District Cooling','GJ'],	
       ['District Heating', 'GJ'],	
       ['Water', 'm3'] 
       ]

       end_uses = [
          'Heating'	,
          'Cooling'	,
          'Interior Lighting'	,
          'Exterior Lighting'	,
          'Interior Equipment'	,
          'Exterior Equipment'	,
          'Fans'	,
          'Pumps'	,
          'Heat Rejection'	,
          'Humidification'	,
          'Heat Recovery'	,
          'Water Systems'	,
          'Refrigeration'	,
          'Generators'	, 	 	 	 	 	 
          'Total End Uses'
          ]

      fuels.each do |fuel_type|
        end_uses.each do |use_type|
          fuel_name = fuel_type[0]
          fuel_units = fuel_type[1]
          value = model.sqlFile().get().execAndReturnFirstDouble("SELECT Value FROM tabulardatawithstrings WHERE ReportName='AnnualBuildingUtilityPerformanceSummary' AND ReportForString='Entire Facility' AND TableName='End Uses' AND RowName='#{use_type}' AND ColumnName='#{fuel_name}' AND Units='#{fuel_units}'")
          if value.empty?
            value = 0.0
          else
            value = value.get
          end
      store_data(runner,  value, "end_use-#{fuel_name}-#{use_type}", fuel_units)
      store_data(runner,  value / @current_building.floorArea() , "eui-#{fuel_name}-#{use_type}", "#{fuel_units}/m2")
          
        end
      end
    # closing the sql file
    sql_file.close



    # reporting final condition
    runner.registerFinalCondition("Saved BTAP results to runner.")

    true
  end # end the run method
end # end the measure

# this allows the measure to be use by the application
BTAPResults.new.registerWithApplication
