
# This class is a data structure to hold information
# generated by the specific individual error checks
class CheckData
  
  attr_accessor :name, :descr
  attr_reader :infos, :warnings, :errors, :causes, :solns
  
  def initialize
    @name = ''
    @descr = ''
    @msgs = []
  end 
    
 end
 