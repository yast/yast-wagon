require "yast/rake"

Yast::Tasks.configuration do |conf|
  #lets ignore license check for now
  conf.skip_license_check << /.*/
end


Rake::Task["osc:sr"].clear_actions

namespace :osc do
  task :sr do
    puts "The package is dropped in openSUSE:Factory, submit request not sent"
  end
end
