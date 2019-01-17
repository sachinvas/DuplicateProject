require 'fileutils'
require 'xcodeproj'

FileUtils.chdir('Release')
destination_proj_name = 'YOUR_DUPLICATE_PROJECT_NAME'
FileUtils.mkdir_p(destination_proj_name)
FileUtils.chdir(destination_proj_name)
FileUtils.mkdir_p(destination_proj_name)

source_proj_name = 'YOUR_ORIGINAL_PROJECT_NAME'
source_project_path = '../../' + source_proj_name + '/' + source_proj_name

# open source project
source_proj = Xcodeproj::Project.open(source_project_path + '.xcodeproj')
print(source_proj, "\n")

# create destination project
destination_proj = Xcodeproj::Project.new(destination_proj_name + '.xcodeproj')

# select the target to be duplicated
source_target = source_proj.targets.find { |item| item.to_s == 'YOUR_ORIGINAL_PROJECT_TARGET' }

# create destination target
destination_target = destination_proj.new_target(source_target.symbol_type, destination_proj_name, source_target.platform_name, source_target.deployment_target)
destination_target.product_name = destination_proj_name

# create destination scheme
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(destination_target)
scheme.set_launch_target(destination_target)
scheme.save_as(destination_proj.path, destination_proj_name)

# copy build_configurations from source to destination
destination_target.build_configurations.map do |item|
  item.build_settings.update(source_target.build_settings(item.name))
end

# move the required files to the destination
source_path = '../../' + source_proj_name + '/YOUR_ORIGINAL_PROJECT_TARGET/.'
FileUtils.cp_r(source_path, destination_proj_name)

# info.plist path
destination_target.build_configurations.each {|bc| bc.build_settings['INFOPLIST_FILE'] = destination_proj_name + '/Info.plist' }


# copy build_phases


def addfiles (direc, current_group, main_target)
  Dir.glob(direc) do |item|
    next if item == '.' or item == '.DS_Store' or item.include? '.framework'

    if File.directory?(item)
      new_folder = File.basename(item)
      if new_folder.to_s == 'Assets.xcassets'
        i = current_group.new_file(item)
        main_target.add_resources([i])
      elsif new_folder.to_s == 'Base.lproj'
        addfiles("#{item}/*", current_group, main_target)
      end
    else
      i = current_group.new_file(item)
      if item.include? ".swift"
        main_target.add_file_references([i])
      elsif item.include? ".storyboard" or item.include? ".xib"
        main_target.add_resources([i])
      end
    end
  end
end

# new group and add source files to it
destination_group = destination_proj.new_group(destination_proj_name)
addfiles("#{destination_proj_name}/*", destination_group, destination_target)

# copy built framework
framework_location = File.dirname(Dir.pwd) + '/' + source_proj_name + '/'
FileUtils.mkdir_p(framework_location)
framework_source_path = source_project_path + '.framework'
FileUtils.cp_r(framework_source_path, framework_location)

# Get useful variables
frameworks_build_phase_source = source_target.build_phases.find { |build_phase| build_phase.to_s == 'FrameworksBuildPhase' }
frameworks_group_destination = destination_proj.groups.find { |group| group.display_name == 'Frameworks' }
frameworks_build_phase_destination = destination_target.build_phases.find { |build_phase| build_phase.to_s == 'FrameworksBuildPhase' }

# Add frameworks
for build_file in frameworks_build_phase_source.files
  frameworks = []
  if build_file.display_name.end_with?('.framework')
    framework_name = build_file.display_name.split('.framework').first
    if framework_name != source_proj_name or framework_name != 'Pods_{YOUR_ORIGINAL_PROJECT_TARGET}App'
      frameworks << framework_name
    end
  end
  destination_target.add_system_frameworks(frameworks)
end

# Add new "Embed Frameworks" build phase to target
embed_frameworks_build_phase = destination_proj.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
embed_frameworks_build_phase.name = 'Embed Frameworks'
embed_frameworks_build_phase.symbol_dst_subfolder_spec = :frameworks
destination_target.build_phases << embed_frameworks_build_phase

# Add framework to target as "Embedded Frameworks"
framework_ref = frameworks_group_destination.new_file("#{framework_location}/#{source_proj_name + '.framework'}")
build_file = embed_frameworks_build_phase.add_file_reference(framework_ref)
frameworks_build_phase_destination.add_file_reference(framework_ref)
build_file.settings = { 'ATTRIBUTES' => ['CodeSignOnCopy', 'RemoveHeadersOnCopy'] }

# Add framework search path to target
['Debug', 'Release'].each do |config|
  paths = ['$(inherited)', '../YOUR_ORIGINAL_PROJECT_NAME/']
  destination_target.build_settings(config)['FRAMEWORK_SEARCH_PATHS'] = paths
end

destination_proj.save