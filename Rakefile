require 'rspec/core'
require 'rspec/core/rake_task'

task :default => :spec do
  desc "Run all specs in spec directory (excluding plugin specs)"
  RSpec::Core::RakeTask.new(:spec)
end