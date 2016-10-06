$LOAD_PATH.unshift File.expand_path('../../../../openstudio-standards/lib', __FILE__)
require 'openstudio'
require 'openstudio/ruleset/ShowRunnerOutput'
require 'minitest/autorun'

require_relative '../measure.rb'

require 'fileutils'



class BTAPReports_Test < MiniTest::Test

  # class level variable
  @@co = OpenStudio::Runmanager::ConfigOptions.new(true)
  
  def epw_path

    puts "Looking in #{@@co.getDefaultEPWLocation.to_s} for weather file"
    epw = OpenStudio::Path.new("#{File.dirname(__FILE__)}/CAN_ON_Ottawa.716280_CWEC.epw")
    assert(File.exist?(epw.to_s))
    
    return epw.to_s
  end

  def run_dir(test_name)
    # always generate test output in specially named 'output' directory so result files are not made part of the measure
    return "#{File.dirname(__FILE__)}/output/#{test_name}"
  end
  
  def model_out_path(test_name)
    return "#{run_dir(test_name)}/test_model.osm"
  end
  
  def sql_path(test_name)
    return "#{run_dir(test_name)}/ModelToIdf/EnergyPlusPreProcess-0/EnergyPlus-0/eplusout.sql"
  end
  
  def report_path(test_name)
    return "#{run_dir(test_name)}/report.html"
  end

  # create test files if they do not exist when the test first runs 
  def setup_test(test_name, idf_output_requests)
  
    @@co.findTools(false, true, false, true)
    
    model_in_path = "#{File.dirname(__FILE__)}/#{test_name}.osm"
    
    if !File.exist?(run_dir(test_name))
      FileUtils.mkdir_p(run_dir(test_name))
    end
    assert(File.exist?(run_dir(test_name)))
    
    if File.exist?(report_path(test_name))
      FileUtils.rm(report_path(test_name))
    end

    assert(File.exist?(model_in_path))
    
    if File.exist?(model_out_path(test_name))
      FileUtils.rm(model_out_path(test_name))
    end

    # convert output requests to OSM for testing, OS App and PAT will add these to the E+ Idf 
    if idf_output_requests.size > 0
      workspace = OpenStudio::Workspace.new("Draft".to_StrictnessLevel, "EnergyPlus".to_IddFileType)
      workspace.addObjects(idf_output_requests)
      rt = OpenStudio::EnergyPlus::ReverseTranslator.new
      request_model = rt.translateWorkspace(workspace)
    end
    
    model = OpenStudio::Model::Model.load(model_in_path).get
    if idf_output_requests.size > 0
      model.addObjects(request_model.objects)
    end
    model.save(model_out_path(test_name), true)

    if !File.exist?(sql_path(test_name))
      puts "Running EnergyPlus"

      wf = OpenStudio::Runmanager::Workflow.new("modeltoidf->energypluspreprocess->energyplus")
      wf.add(@@co.getTools())
      job = wf.create(OpenStudio::Path.new(run_dir(test_name)), OpenStudio::Path.new(model_out_path(test_name)), OpenStudio::Path.new(epw_path))

      rm = OpenStudio::Runmanager::RunManager.new
      rm.enqueue(job, true)
      rm.waitForFinished
    end
  end

  def test_model_meter
  
    test_name = "test_model"

    # create an instance of the measure
    measure = BTAPReports.new

    # create an instance of a runner
    runner = OpenStudio::Ruleset::OSRunner.new
    runner.setLastOpenStudioModelPath(OpenStudio::Path.new("#{File.dirname(__FILE__)}/#{test_name}.osm"))
    
    # Load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = OpenStudio::Path.new(File.dirname(__FILE__) + "/#{test_name}.osm")
    model = translator.loadModel(path)
    assert((not model.empty?))
    model = model.get    
    
    # Get arguments and test that they are what we are expecting
    arguments = measure.arguments()
    argument_map = OpenStudio::Ruleset::OSArgumentMap.new
    
    # get the energyplus output requests, this will be done automatically by OS App and PAT
    idf_output_requests = measure.energyPlusOutputRequests(runner, argument_map)
    assert(idf_output_requests.size == 0)

    # mimic the process of running this measure in OS App or PAT
    setup_test(test_name, idf_output_requests)
    puts model_out_path(test_name)
    puts sql_path(test_name)
    puts epw_path
    assert(File.exist?(model_out_path(test_name)))
    assert(File.exist?(sql_path(test_name)))
    assert(File.exist?( epw_path ))

    # set up runner, this will happen automatically when measure is run in PAT or OpenStudio
    runner.setLastOpenStudioModelPath(OpenStudio::Path.new(model_out_path(test_name)))
    runner.setLastEpwFilePath(epw_path)
    runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sql_path(test_name)))

    # delete the output if it exists
    if File.exist?(report_path(test_name))
      FileUtils.rm(report_path(test_name))
    end
    assert(!File.exist?(report_path(test_name)))
    
    # temporarily change directory to the run directory and run the measure
    start_dir = Dir.pwd
    begin
      Dir.chdir(run_dir(test_name))

      # run the measure
      measure.run(runner, argument_map)
      result = runner.result
      show_output(result)
      assert_equal("Success", result.value.valueName)
    ensure
      Dir.chdir(start_dir)
    end
    
    # make sure the report file exists
    #assert(File.exist?(report_path(test_name)))
  end

  def test_model_variable
  
    test_name = "test_model_2"

    # create an instance of the measure
    measure = BTAPReports.new

    # create an instance of a runner
    runner = OpenStudio::Ruleset::OSRunner.new
    runner.setLastOpenStudioModelPath(OpenStudio::Path.new("#{File.dirname(__FILE__)}/#{test_name}.osm"))
    
    # Load the test model
    translator = OpenStudio::OSVersion::VersionTranslator.new
    path = OpenStudio::Path.new(File.dirname(__FILE__) + "/#{test_name}.osm")
    model = translator.loadModel(path)
    assert((not model.empty?))
    model = model.get    
    
    # Get arguments and test that they are what we are expecting
    arguments = measure.arguments()
    argument_map = OpenStudio::Ruleset::OSArgumentMap.new
    
    # get the energyplus output requests, this will be done automatically by OS App and PAT
    idf_output_requests = measure.energyPlusOutputRequests(runner, argument_map)
    assert(idf_output_requests.size == 0)

    # mimic the process of running this measure in OS App or PAT
    setup_test(test_name, idf_output_requests)
    
    assert(File.exist?(model_out_path(test_name)))
    assert(File.exist?(sql_path(test_name)))
    assert(File.exist?(epw_path))

    # set up runner, this will happen automatically when measure is run in PAT or OpenStudio
    runner.setLastOpenStudioModelPath(OpenStudio::Path.new(model_out_path(test_name)))
    runner.setLastEpwFilePath(epw_path)
    runner.setLastEnergyPlusSqlFilePath(OpenStudio::Path.new(sql_path(test_name)))

    # delete the output if it exists
    if File.exist?(report_path(test_name))
      FileUtils.rm(report_path(test_name))
    end
    assert(!File.exist?(report_path(test_name)))
    
    # temporarily change directory to the run directory and run the measure
    start_dir = Dir.pwd
    begin
      Dir.chdir(run_dir(test_name))

      # run the measure
      measure.run(runner, argument_map)
      result = runner.result
      show_output(result)
      assert_equal("Success", result.value.valueName)
    ensure
      Dir.chdir(start_dir)
    end
    
    # make sure the report file exists
    #assert(File.exist?(report_path(test_name)))
  end  
  
end
