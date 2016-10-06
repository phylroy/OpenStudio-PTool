class XcelEDAReportingandQAQC < OpenStudio::Ruleset::ReportingUserScript

  def unmet_hrs_check

    # Checks the number of unmet hours in the model

    # TODO
    # have the xcel protocol set the reporting tolerance for deltaF (DOE2 has 0.55C tolerance - Brent suggests 0.55C for E+ too)
    # could we do a custom report to show the thermostat schedules? during occupied and unoccupied times
  
    check = CheckData.new
    check.name = "Unmet Hours Check"
    check.descr = "Check that the heating and cooling systems are meeting their setpoints for the entire simulation period."

    # Setup the queries
    heating_setpoint_unmet_query = "SELECT Value FROM TabularDataWithStrings WHERE (ReportName='SystemSummary') AND (ReportForString='Entire Facility') AND (TableName='Time Setpoint Not Met') AND (RowName = 'Facility') AND (ColumnName='During Heating')"
    cooling_setpoint_unmet_query = "SELECT Value FROM TabularDataWithStrings WHERE (ReportName='SystemSummary') AND (ReportForString='Entire Facility') AND (TableName='Time Setpoint Not Met') AND (RowName = 'Facility') AND (ColumnName='During Cooling')"
    
    # Get the info
    heating_setpoint_unmet = @sql.execAndReturnFirstDouble(heating_setpoint_unmet_query)
    cooling_setpoint_unmet = @sql.execAndReturnFirstDouble(cooling_setpoint_unmet_query)
    
    # Make sure all the data are availalbe
    if heating_setpoint_unmet.empty? or cooling_setpoint_unmet.empty?
      check.msgs << ['warn',"Hours heating or cooling unmet data unavailable; check not run."]
      return check
    end
    
    # Aggregate heating and cooling hrs
    heating_or_cooling_setpoint_unmet = heating_setpoint_unmet.get + cooling_setpoint_unmet.get    
    
    # Warn if heating + cooling unmet hours > 300
    if heating_or_cooling_setpoint_unmet > 300
      check.msgs << ['error',"Hours heating or cooling unmet is #{heating_or_cooling_setpoint_unmet}, greater than the 90.1 Appendix G limit of 300 hrs."]
    end

    
    return check
    
  end

end  