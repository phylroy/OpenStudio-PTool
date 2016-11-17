#see the URL below for information on how to write OpenStudio measures
# http://openstudio.nrel.gov/openstudio-measure-writing-guide

#see the URL below for information on using life cycle cost objects in OpenStudio
# http://openstudio.nrel.gov/openstudio-life-cycle-examples

#see the URL below for access to C++ documentation on model objects (click on "model" in the main window to view model objects)
# http://openstudio.nrel.gov/sites/openstudio.nrel.gov/files/nv_data/cpp_documentation_it/model/html/namespaces.html

#start the measure
class ListOfConstructions < OpenStudio::Ruleset::ModelUserScript
  
  #define the name that a user will see, this method may be deprecated as
  #the display name in PAT comes from the name field in measure.xml
  def name
    return "ListOfConstructions"
  end
  
  #define the arguments that the user will input
  def arguments(model)
    args = OpenStudio::Ruleset::OSArgumentVector.new

    
    return args
  end #end the arguments method

  #define what happens when the measure is run
  def run(model, runner, user_arguments)
    super(model, runner, user_arguments)
    
    #use the built-in error checking 
    if not runner.validateUserArguments(arguments(model), user_arguments)
      return false
    end

    #get constructions
    constructions = model.getConstructions

    #reporting initial condition of model
    runner.registerInitialCondition("The building contains #{constructions.size} constructions.")

    #arrays for csv
    header = ["Construction Name","Type","u-factor (W/m^2*K)","R-value (m^2*K/W)","Material 1","Material 2","Material 3","Material 4","Material 5"]
    values = []

    #loop through constructions
    constructions.sort.each do |construction|
      row = []
      row << construction.name

      #get u-factor or thermal conductance
      if construction.isOpaque
        row << "Opaque"
        row << ""
        if not construction.thermalConductance.empty?
          row << 1/construction.thermalConductance.get  #get R-value vs. conductance
        else
          row << "Can't calculate"
        end
      end

      if construction.isFenestration
        row << "Fenestration"
        if not construction.uFactor.empty?
          row << construction.uFactor.get
        else
          row << "Can't calculate"
        end
        row << ""
      end

      #get material names
      materials = construction.layers

      #loop through materials
      materials.each do |material|
        row << material.name
      end #end of materials.each do

      puts row.join(",")
      values << row
    end #end of constructions.each do
    puts ""

    # if we want this report could write out a csv, html, or any other file here
    runner.registerInfo("Writing CSV report 'report.csv'")
    File.open("report.csv", 'w') do |file|
      file.puts header.join(',')
      values.each do |row|
        file.puts row.join(',')
      end
    end

    #reporting final condition of model
    runner.registerFinalCondition("Wrote CSV for #{constructions.size} constructions.")
    
    return true
 
  end #end the run method

end #end the measure

#this allows the measure to be use by the application
ListOfConstructions.new.registerWithApplication