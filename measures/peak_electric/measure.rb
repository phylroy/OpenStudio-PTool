# see the URL below for information on how to write OpenStudio measures
# http://nrel.github.io/OpenStudio-user-documentation/reference/measure_writing_guide/

require 'erb'

#start the measure
class PeakElectric < OpenStudio::Ruleset::ReportingUserScript

  # human readable name
  def name
    return "Peak Electricity Annual Demand"
  end

  # human readable description
  def description
    return "Test measure to report annual peak electric load"
  end

  # human readable description of modeling approach
  def modeler_description
    return "Replace this text with an explanation for the energy modeler specifically.  It should explain how the measure is modeled, including any requirements about how the baseline model must be set up, major assumptions, citations of references to applicable modeling resources, etc.  The energy modeler should be able to read this description and understand what changes the measure is making to the model and why these changes are being made.  Because the Modeler Description is written for an expert audience, using common abbreviations for brevity is good practice."
  end

  # define the arguments that the user will input
  def arguments()
    args = OpenStudio::Ruleset::OSArgumentVector.new

    # this measure does not require any user arguments, return an empty list

    return args
  end 
  
  # return a vector of IdfObject's to request EnergyPlus objects needed by the run method
  def energyPlusOutputRequests(runner, user_arguments)
    super(runner, user_arguments)

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

    sqlFile = runner.lastEnergyPlusSqlFile
    if sqlFile.empty?
      runner.registerError("Cannot find last sql file.")
      return false
    end
    sqlFile = sqlFile.get
    model.setSqlFile(sqlFile)

    # get peak electric load
    query = "SELECT Value FROM tabulardatawithstrings WHERE ReportName='DemandEndUseComponentsSummary' and TableName='End Uses' and RowName= 'Total End Uses' and ColumnName= 'Electricity'"
    results = sqlFile.execAndReturnFirstDouble(query).get
    runner.registerValue('peak_elec_demand',results)
    runner.registerInfo("Annual Peak Electric Demand is #{results} (W).")

    # close the sql file
    sqlFile.close()

    return true
 
  end

end

# register the measure to be used by the application
PeakElectric.new.registerWithApplication
