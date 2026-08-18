# One-time setup: inserts a Run Script build phase on the Runner target
# that re-applies patch_registrant_for_simulator.sh before every compile —
# see that script's own doc comment for why this needs to run on every
# single build rather than just once. Idempotent: safe to re-run (checks
# for an existing phase with the same name before adding another).
#
# Usage: GEM_HOME="$(dirname $(dirname $(readlink -f $(which pod))))" ruby setup_simulator_patch.rb
# (this repo's CocoaPods install bundles the xcodeproj gem this needs — see
# its own invocation in the terminal history for the exact GEM_HOME used)

require 'xcodeproj'

project_path = File.join(__dir__, 'Runner.xcodeproj')
project = Xcodeproj::Project.open(project_path)

runner_target = project.targets.find { |t| t.name == 'Runner' }
raise "Runner target not found in #{project_path}" unless runner_target

phase_name = 'Guard DeepAR out of Simulator builds'
existing = runner_target.build_phases.find { |p| p.respond_to?(:name) && p.name == phase_name }

if existing
  puts "Build phase '#{phase_name}' already present — nothing to do."
else
  phase = runner_target.new_shell_script_build_phase(phase_name)
  phase.shell_script = '"${SRCROOT}/Runner/patch_registrant_for_simulator.sh"'
  # Must run before Compile Sources, since it rewrites a .m file that
  # phase is about to compile — insert_at_index puts it first among all
  # build phases (safe: this phase has no inputs of its own to order
  # against, it only needs to precede compilation).
  compile_index = runner_target.build_phases.index do |p|
    p.is_a?(Xcodeproj::Project::Object::PBXSourcesBuildPhase)
  end
  runner_target.build_phases.move(phase, compile_index) if compile_index

  project.save
  puts "Added build phase '#{phase_name}' to Runner target, before Compile Sources."
end
