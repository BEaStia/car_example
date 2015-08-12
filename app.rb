require 'eventmachine'
require 'em-http-request'

require './parser/AutoruParser'

autoruParser = AutoruParser.new
autoruParser.update_cars_makers
result = autoruParser.get_new_cars

p result