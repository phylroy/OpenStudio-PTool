require 'erb'

#start the measure
class NRELOpenStudioQAQCChecks < OpenStudio::Ruleset::ReportingUserScript
  
  #define the name that a user will see, this method may be deprecated as
  #the display name in PAT comes from the name field in measure.xml
  def name
    return "NRELOpenStudioQAQCChecks"
  end
  
  #define the arguments that the user will input
  def arguments()
    args = OpenStudio::Ruleset::OSArgumentVector.new
    
    return args
  end #end the arguments method

  #define what happens when the measure is run
  def run(runner, user_arguments)
    super(runner, user_arguments)
    
    # Use the built-in error checking 
    if not runner.validateUserArguments(arguments(), user_arguments)
      return false
    end

    # Get the last model and sql file
    @model = runner.lastOpenStudioModel
    if @model.empty?
      runner.registerError("Cannot find last model.")
      return false
    end
    @model = @model.get
    
    @sql = runner.lastEnergyPlusSqlFile
    if @sql.empty?
      runner.registerError("Cannot find last sql file.")
      return false
    end
    @sql = @sql.get
    @model.setSqlFile(@sql)
 
    # Load some the helper libraries
    @resource_path = "#{File.dirname(__FILE__)}/resources"
    require "#{@resource_path}/Model.rb"
    require "#{@resource_path}/AirTerminalSingleDuctParallelPIUReheat.rb"
    require "#{@resource_path}/AirTerminalSingleDuctVAVReheat.rb"
    require "#{@resource_path}/AirTerminalSingleDuctUncontrolled.rb"
    require "#{@resource_path}/AirLoopHVAC.rb"
    require "#{@resource_path}/FanConstantVolume.rb"
    require "#{@resource_path}/FanVariableVolume.rb"
    require "#{@resource_path}/CoilHeatingElectric.rb"
    require "#{@resource_path}/CoilHeatingGas.rb"
    require "#{@resource_path}/CoilHeatingWater.rb"
    require "#{@resource_path}/CoilCoolingDXSingleSpeed.rb"
    require "#{@resource_path}/CoilCoolingDXTwoSpeed.rb"
    require "#{@resource_path}/CoilCoolingWater.rb"
    require "#{@resource_path}/ControllerOutdoorAir.rb"
    require "#{@resource_path}/PlantLoop.rb"
    require "#{@resource_path}/PumpConstantSpeed.rb"
    require "#{@resource_path}/PumpVariableSpeed.rb"
    require "#{@resource_path}/BoilerHotWater.rb"
    require "#{@resource_path}/ChillerElectricEIR.rb"
    require "#{@resource_path}/CoolingTowerSingleSpeed.rb"
    require "#{@resource_path}/ControllerWaterCoil.rb" 
    require "#{@resource_path}/ThermalZone.rb" 
 
    # Load the Check class (holds errors, warnings, infos, etc)
    require "#{@resource_path}/CheckData"
 
    # Load the qaqc checks
    require "#{@resource_path}/EUI"
    require "#{@resource_path}/UnmetHrs"
    require "#{@resource_path}/DCV"

    # Store the check results to report them later
    checks = []
    
    # EUI check
    checks << eui_check
  
    # Unmet hours check
    checks << unmet_hrs_check

    # DCV missing check
    checks << dcv_check

    # VAV min flow too low check
    # TODO
    
    # OA damper open at night check
    # TODO
      
    # Report the results of the checks
    checks.each do |check|

      # Report the info in PAT
      runner.registerInfo(check.name)
      runner.registerInfo(check.descr)
      
      check.msgs.each do |info|
        msg_type = info[0]
        
        case msg_type
        when 'info'
          runner.registerInfo(msg)
        when 'cause'
          runner.registerInfo(msg)
        when 'warn'
          runner.registerWarning(msg)
        when 'error'
          runner.registerError(msg)
        end
        
      end
      
      # Report the info in an html report
      # TODO 
      
    end

    
    # Close the sql file
    @sql.close

    return true
 
  end # End the run method

end # End the measure

#this allows the measure to be use by the application
NRELOpenStudioQAQCChecks.new.registerWithApplication
