require 'openstudio'

require 'openstudio/ruleset/ShowRunnerOutput'

require "#{File.dirname(__FILE__)}/../measure.rb"

require 'fileutils'

require 'minitest/autorun'

# In order to test without having to run energyplus, we mock out some of the methods called by
# the measure.  We give ourselves the ability to insert arbitrary time series by storing
# series in the $serieses global variable.  Instead of loading series data from from
# the sql file, our measure will get data from the $serieses entry with the key matching
# the name that was requested.
$serieses = Hash.new

#class OpenStudio::Ruleset::OSRunner
#  def lastEnergyPlusSqlFile
#	puts "Using fake SQL File"
#    sqlFile = OpenStudio::SqlFile.new(OpenStudio::Path.new("#{File.dirname(__FILE__)}/sqlfile.sql"))
#  end
#end

class OpenStudio::SqlFile
  def timeSeries(envperiod, rate, name, index)
    return $serieses["#{name}|#{index}"] || OpenStudio::TimeSeries.new
  end
end

class OpenStudio::TimeSeries
  def get
    self
  end
  
  def empty?
    false
  end
end

class Array
  def to_vector
    v = OpenStudio::Vector.new(self.size)
	self.each_with_index { |o, i| v[i] = o }
	return v
  end
end

class VentilationQAQC_Test < MiniTest::Unit::TestCase
  TEN_FT = 3.048
  EIGHT_FT = 2.4384

  
  def sqlPath
    return "#{File.dirname(__FILE__)}/sqlfile.sql"
  end
  
  def reportPath
    return "./report.html"
  end
  
  # create test files if they do not exist
  def setup
	
    # create an instance of the measure
    @measure = VentilationQAQC.new
    
    #create an instance of the runner
    @runner = OpenStudio::Ruleset::OSRunner.new	
	
    # get arguments    
    @arguments = @measure.arguments()

    # make argument map
    make_argument_map
	
    # Make an empty model
    @model = OpenStudio::Model::Model.new
	@runner.setLastOpenStudioModel(@model)
	
	# Create a fake sql file - our measure will crash if @runner has no sql file set.
	# We don't get data from this file because we get data from our patched SqlFile class instead (see above)
	sqlFile = OpenStudio::SqlFile.new(OpenStudio::Path.new(sqlPath))
	@runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sqlPath))
	
	$serieses["Zone Mechanical Ventilation Mass Flow Rate|ZONE1"] = OpenStudio::TimeSeries.new(OpenStudio::Date.new, OpenStudio::Time.new(1.0), (0..364).to_a.to_vector, "m^3/s")
  end
  
  def make_outdoor_air
	outdoorAir = OpenStudio::Model::DesignSpecificationOutdoorAir.new(@model)
	outdoorAir.setOutdoorAirFlowRate(cfm(500.0))
	outdoorAir.setOutdoorAirFlowperPerson(cfmperperson(120))
	outdoorAir.setOutdoorAirFlowperFloorArea(cfmpersf(0.5))
	outdoorAir.setOutdoorAirFlowAirChangesperHour(2.3)
	return outdoorAir
  end
  
  def make_space_and_zone
	zone = OpenStudio::Model::ThermalZone.new(@model)
	zone.setName("Zone1")
  
	# Make a space 10 ft x 10 ft, 8 ft high with 10 people in it's own thermal zone
	space = OpenStudio::Model::Space::fromFloorPrint([OpenStudio::Point3d.new(0, TEN_FT, 0), OpenStudio::Point3d.new(TEN_FT, TEN_FT, 0), OpenStudio::Point3d.new(TEN_FT, 0, 0), OpenStudio::Point3d.new(0, 0, 0)], EIGHT_FT, @model).get
	space.setName("SpaceUnderTest")
	space.setThermalZone(zone)
	space.setNumberOfPeople(10)
	
	return space, zone
  end
  
  def cfm_to_m3s(cfm)
	OpenStudio.convert(cfm, "cfm", "m^3/s").get
  end
  
  def cfmpersf_to_m3spersm(cfm)
	OpenStudio.convert(cfm, "cfm/ft^2", "m/s").get
  end
  
  def cfm(cfm)
	OpenStudio::Quantity.new(cfm, OpenStudio::createUnit("cfm").get)
  end
  
  def cfmperperson(cfm)
	OpenStudio::Quantity.new(cfm, OpenStudio::createUnit("cfm/person").get)
  end
  
  def cfmpersf(cfm)
	OpenStudio::Quantity.new(cfm, OpenStudio::createUnit("cfm/ft^2").get)
  end
  
  # the actual test
  def test_OutdoorAirCalculatedFromSum
	# Create a single space with a DesignSpecificationOutdoorAir
	# Setting the outdoor air method to Sum, the resulting outdoor ventilation
	# should be the sum of the calculated cfm of the four DesignSpecificationOutdoorAir inputs
	space, zone = make_space_and_zone
	outdoorAir = make_outdoor_air
	outdoorAir.setOutdoorAirMethod("Sum")
	space.setDesignSpecificationOutdoorAir(outdoorAir)
	
    @measure.run(@runner, @argument_map)
    result = @runner.result

	# Make sure the measure ran successfully
	assert_equal OpenStudio::Ruleset::OSResultValue.new(0), result.value
	
	space = @measure.outData[:spaceCollection][0]
	
	assert_equal "SpaceUnderTest", space[:name]

	expected_cfm = 500.0 + 120*10 + 0.5 * 100 + 2.3 / 60 * 800
	
	# Test cfm/person (10 persons in space)
	assert_in_delta expected_cfm/10.0, space[:outsideAirPerPerson], 0.001
  end  

  # the actual test
  def test_OutdoorAirCalculatedFromMaximum
	# Create a single space with a DesignSpecificationOutdoorAir
	# Setting the outdoor air method to Maximum, the resulting outdoor ventilation
	# should be the maximum calculated cfm of the four DesignSpecificationOutdoorAir inputs
	space, zone = make_space_and_zone
	outdoorAir = make_outdoor_air
	outdoorAir.setOutdoorAirMethod("Maximum")
	space.setDesignSpecificationOutdoorAir(outdoorAir)
	
    @measure.run(@runner, @argument_map)
    result = @runner.result

	# Make sure the measure ran successfully
	assert_equal result.value, OpenStudio::Ruleset::OSResultValue.new(0)
	
	space = @measure.outData[:spaceCollection][0]
	
	assert_equal "SpaceUnderTest", space[:name]

	expected_cfm = [500.0, 120*10, 0.5 * 100, 2.3 / 60 * 800].max
	
	assert_in_delta expected_cfm/10.0, space[:outsideAirPerPerson], 0.001
  end  

  def test_SpaceWithNoOutdoorAirHasNoPresenceInReport
	# Verify that our measure runs correctly when there are spaces with no attached
	# SpaceInfiltrationDesignFlowRate or DesignSpecificationOutdoorAir objects
	space, zone = make_space_and_zone
	
    @measure.run(@runner, @argument_map)
    result = @runner.result

	assert_equal OpenStudio::Ruleset::OSResultValue.new(0), result.value
	
#	assert_equal 0, @measure.outData[:spaceCollection].length
  end  
  
  def test_InfiltrationCalculatedFromFlowRate
	# Create one space with a single SpaceInfiltrationDesignFlowRate
	# The design flow rate is 500 cfm/space, so the total air changes are
	# easily calculated from the space volume.
    space, _ = make_space_and_zone
	
    designflow1 = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(@model)
	designflow1.setDesignFlowRate(cfm_to_m3s(500))
	
	designflow1.setSpace(space)
	
    @measure.run(@runner, @argument_map)
    result = @runner.result

	# Make sure the measure ran successfully
	assert_equal OpenStudio::Ruleset::OSResultValue.new(0), result.value
	
	spaceRow = @measure.outData[:spaceCollection][0]
	
	assert_equal "SpaceUnderTest", spaceRow[:name]

	expected_ach = 500 * 60.0 / 800.0
	
	assert_in_delta expected_ach, spaceRow[:airChangesPerHour], 0.001
  end
  
  def test_InfiltrationSummedAcrossDesignFlowRates
    # Create one space with two SpaceInfilatrationDesignFlowRates -
	# Flow rate one is set to 500 cfm/space
	# Flow rate two is 1 cfm/square foot
	# The total ACH for the space should be the sum of these two SpaceInfilatrationDesignFlowRates
    space, _ = make_space_and_zone
	
    designflow1 = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(@model)
	designflow1.setDesignFlowRate(cfm_to_m3s(500))
	designflow1.setSpace(space)
	
    designflow2 = OpenStudio::Model::SpaceInfiltrationDesignFlowRate.new(@model)
	designflow2.setFlowperSpaceFloorArea(cfmpersf_to_m3spersm(1))
	designflow2.setSpace(space)

    @measure.run(@runner, @argument_map)
    result = @runner.result

	# Make sure the measure ran successfully
	assert_equal OpenStudio::Ruleset::OSResultValue.new(0), result.value
	
	spaceRow = @measure.outData[:spaceCollection][0]
	
	assert_equal "SpaceUnderTest", spaceRow[:name]

	expected_ach = (500 + 1*100) * 60.0 / 800.0
	
	assert_in_delta expected_ach, spaceRow[:airChangesPerHour], 0.001
  end
  
  def test_AreaWeightedZoneCFM
    space1, zone = make_space_and_zone
	space2 = OpenStudio::Model::Space::fromFloorPrint([OpenStudio::Point3d.new(0, TEN_FT*2, 0), OpenStudio::Point3d.new(TEN_FT*2, TEN_FT*2, 0), OpenStudio::Point3d.new(TEN_FT*2, 0, 0), OpenStudio::Point3d.new(0, 0, 0)], EIGHT_FT, @model).get
	space2.setName("SpaceUnderTest2")
	space2.setThermalZone(zone)
	space2.setNumberOfPeople(5)
	
	outdoorAir1 = make_outdoor_air
	outdoorAir1.setOutdoorAirMethod("Maximum") # Airflow will be 120 x 10 people
	space1.setDesignSpecificationOutdoorAir(outdoorAir1)
	outdoorAir2 = make_outdoor_air
	outdoorAir2.setOutdoorAirMethod("Maximum") # Airflow will be 120 x 5 people
	space2.setDesignSpecificationOutdoorAir(outdoorAir1)
	
    @measure.run(@runner, @argument_map)
    result = @runner.result

	# Make sure the measure ran successfully
	assert_equal OpenStudio::Ruleset::OSResultValue.new(0), result.value
	
	zoneRow = @measure.outData[:zoneCollection][0]
	
	expected_cfm = (120.0*10.0*100.0 + 120.0*5.0*400.0) / (400.0 + 100.0)
	
	assert_in_delta expected_cfm, zoneRow[:zoneWeightedCFM], 0.001
  end
  
  def test_OutsideAirScheduling_AllGood
    make_space_and_zone
    ventRate = Array.new(100) { |i| 0.0 } + Array.new(8660) { |i| 50 }
	occupancy = Array.new(100) { |i| 0.0 } + Array.new(8660) { |i| 27 }
	$serieses["Zone Mechanical Ventilation Mass Flow Rate|ZONE1"] = OpenStudio::TimeSeries.new(OpenStudio::Date.new, OpenStudio::Time.new(0.0416666), ventRate.to_vector, "m^3/s")
	$serieses["Zone People Occupant Count|ZONE1"] = OpenStudio::TimeSeries.new(OpenStudio::Date.new, OpenStudio::Time.new(0.0416666), occupancy.to_vector, "m^3/s")
	
    @measure.run(@runner, @argument_map)
    result = @runner.result

	# Make sure the measure ran successfully
	assert_equal OpenStudio::Ruleset::OSResultValue.new(0), result.value

	warnings = @measure.outData[:warnings]
	# There should be no warning messages about OA scheduling
	assert_equal warnings.length, 0, "Expected no warnings"
  end
  
  def test_OutsideAirScheduling_UnoccupiedVentilation
    make_space_and_zone

    ventRate = Array.new(80) { |i| 0.0 } + Array.new(8680) { |i| 50 }
	occupancy = Array.new(100) { |i| 0.0 } + Array.new(8660) { |i| 27 }
	$serieses["Zone Mechanical Ventilation Mass Flow Rate|ZONE1"] = OpenStudio::TimeSeries.new(OpenStudio::Date.new, OpenStudio::Time.new(0.0416666), ventRate.to_vector, "m^3/s")
	$serieses["Zone People Occupant Count|ZONE1"] = OpenStudio::TimeSeries.new(OpenStudio::Date.new, OpenStudio::Time.new(0.0416666), occupancy.to_vector, "m^3/s")
	
    @measure.run(@runner, @argument_map)
    result = @runner.result

	# Make sure the measure ran successfully
	assert_equal OpenStudio::Ruleset::OSResultValue.new(0), result.value

	# There should be a warning message about OA scheduling
	warnings = @measure.outData[:warnings]
	assert_equal 1, warnings.length, "Expected one warning"
	assert /Zone1.*appears to have mechanical ventilation during periods when the zone is unoccupied/ =~ warnings[0]
  end
  
  def test_OutsideAirScheduling_LightlyOccupiedVentilation
    make_space_and_zone

    ventRate = Array.new(8760) { |i| 50 }
	occupancy = Array.new(1600) { |i| 0.4 } + Array.new(7160) { |i| 10 }
	$serieses["Zone Mechanical Ventilation Mass Flow Rate|ZONE1"] = OpenStudio::TimeSeries.new(OpenStudio::Date.new, OpenStudio::Time.new(0.0416666), ventRate.to_vector, "m^3/s")
	$serieses["Zone People Occupant Count|ZONE1"] = OpenStudio::TimeSeries.new(OpenStudio::Date.new, OpenStudio::Time.new(0.0416666), occupancy.to_vector, "m^3/s")
	
    @measure.run(@runner, @argument_map)
    result = @runner.result

	# Make sure the measure ran successfully
	assert_equal OpenStudio::Ruleset::OSResultValue.new(0), result.value

	# There should be a warning message about OA scheduling
	warnings = @measure.outData[:warnings]
	assert_equal 1, warnings.length, "Expected one warning"
	assert /Zone1.*appears to have mechanical ventilation during periods when the zone is lightly occupied/ =~ warnings[0], "Actual text #{warnings[0]} not matched"
  end
  
  def test_OutsideAirScheduling_AllGood
    ventRate = Array.new(100) { |i| 0.0 } + Array.new(8660) { |i| 50 }
	occupancy = Array.new(100) { |i| 0.0 } + Array.new(8660) { |i| 27 }
	$serieses["Zone Mechanical Ventilation Mass Flow Rate|ZONE1"] = OpenStudio::TimeSeries.new(OpenStudio::Date.new, OpenStudio::Time.new(0.0416666), ventRate.to_vector, "m^3/s")
	$serieses["Zone People Occupant Count|ZONE1"] = OpenStudio::TimeSeries.new(OpenStudio::Date.new, OpenStudio::Time.new(0.0416666), occupancy.to_vector, "m^3/s")
	
    @measure.run(@runner, @argument_map)
    result = @runner.result

	# Make sure the measure ran successfully
	assert_equal OpenStudio::Ruleset::OSResultValue.new(0), result.value

	# There should be no warning messages about OA scheduling
	assert_equal 0, result.warnings.length, "Expected no warnings"
  end
  
  def make_argument_map
    argMap = {
      "measure_zone" => "All Zones"
    }
    @argument_map = OpenStudio::Ruleset::OSArgumentMap.new
    argMap.each { | key, value | set_argument(key, value) }
  end 
  
  def set_argument( key, value)
    arg = @arguments.find { |a| a.name == key }
    refute_nil arg, "Expected to find argument of name #{key}, but didn't."
    
    newArg = arg.clone
    assert(newArg.setValue(value), "Could not set argument #{key} to #{value}")
    @argument_map[key] = newArg
  end 
  
end



