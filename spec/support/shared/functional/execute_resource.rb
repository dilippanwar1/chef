#
# Author:: Adam Edwards (<adamed@chef.io>)
# Copyright:: Copyright (c) 2015 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

shared_context "alternate user identity" do
  let(:windows_alternate_user) {"chef%02d%02d%02d" %[Time.now.year % 100, Time.now.month, Time.now.day]}
  let(:windows_alternate_user_password) { 'lj28;fx3T!x,2'}
  let(:windows_alternate_user_qualified) { "#{ENV['COMPUTERNAME']}\\#{windows_alternate_user}" }

  include Chef::Mixin::ShellOut

  before do
    shell_out!("net.exe user /delete #{windows_alternate_user}", returns: [0,2])
    shell_out!("net.exe user /add #{windows_alternate_user} \"#{windows_alternate_user_password}\"")
  end

end

shared_context "a command that can be executed as an alternate user" do
  include_context "alternate user identity"

  let(:script_output_dir) { Dir.mktmpdir }
  let(:script_output_path) { File.join(script_output_dir, make_tmpname("chef_execute_identity_test")) }
  let(:script_output) { File.read(script_output_path) }

  include Chef::Mixin::ShellOut

  before do
    shell_out!("icacls \"#{script_output_dir.gsub(/\//,'\\')}\" /grant \"authenticated users:(F)\"")
  end

  after do
    File.delete(script_output_path) if File.exists?(script_output_path)
    Dir.rmdir(script_output_dir) if Dir.exists?(script_output_dir)
    shell_out("net.exe user /delete #{windows_alternate_user}")
  end
end

shared_examples_for "an execute resource that supports alternate user identity" do
  context "when running on Windows", :windows_only do

    include_context "a command that can be executed as an alternate user"

    let(:windows_current_user) { ENV['USERNAME'] }
    let(:windows_current_user_qualified) { "#{ENV['COMPUTERNAME']}\\#{windows_current_user}" }
    let(:resource_identity_command) { "powershell.exe -noprofile -command \"import-module microsoft.powershell.utility;([Security.Principal.WindowsPrincipal]([Security.Principal.WindowsIdentity]::GetCurrent())).identity.name | out-file -encoding ASCII '#{script_output_path}'\"" }

    let(:execute_resource) {
      resource.user(windows_alternate_user)
      resource.password(windows_alternate_user_password)
      resource.send(resource_command_property, resource_identity_command)
      resource
    }

    it "executes the process as an alternate user" do
      expect(windows_current_user.length).to be > 0
      expect { execute_resource.run_action(:run) }.not_to raise_error
      expect(script_output.chomp.length).to be > 0
      expect(script_output.chomp.downcase).to eq(windows_alternate_user_qualified.downcase)
      expect(script_output.chomp.downcase).not_to eq(windows_current_user.downcase)
      expect(script_output.chomp.downcase).not_to eq(windows_current_user_qualified.downcase)
    end

    let(:windows_alternate_user_password_invalid) { "#{windows_alternate_user_password}x" }

    it "raises an exception if the user's password is invalid" do
      execute_resource.password(windows_alternate_user_password_invalid)
      expect { execute_resource.run_action(:run) }.to raise_error(SystemCallError)
    end
  end
end

shared_examples_for "a resource with a guard specifying an alternate user identity" do
  context "when running on Windows", :windows_only do
    include_context "alternate user identity"

    let(:resource_command_property) { :command }

    let(:powershell_equal_to_alternate_user) { '-eq' }
    let(:powershell_not_equal_to_alternate_user) { '-ne' }
    let(:guard_identity_command) { "powershell.exe -noprofile -command \"import-module microsoft.powershell.utility;exit @(392,0)[[int32](([Security.Principal.WindowsPrincipal]([Security.Principal.WindowsIdentity]::GetCurrent())).Identity.Name #{comparison_to_alternate_user} '#{windows_alternate_user_qualified}')]\"" }

    before do
      resource.guard_interpreter(guard_interpreter_resource)
    end

    context "when the guard expression is true if the user is alternate and false otherwise" do
      let(:comparison_to_alternate_user) { powershell_equal_to_alternate_user }

      it "causes the resource to be updated for only_if" do
        resource.only_if(guard_identity_command, {user: windows_alternate_user, password: windows_alternate_user_password})
        resource.run_action(:run)
        expect(resource).to be_updated_by_last_action
      end

      it "causes the resource to not be updated for not_if" do
        resource.not_if(guard_identity_command, {user: windows_alternate_user, password: windows_alternate_user_password})
        resource.run_action(:run)
        expect(resource).not_to be_updated_by_last_action
      end
    end

    context "when the guard expression is false if the user is alternate and true otherwise" do
      let(:comparison_to_alternate_user) { powershell_not_equal_to_alternate_user }

      it "causes the resource not to be updated for only_if" do
        resource.only_if(guard_identity_command, {user: windows_alternate_user, password: windows_alternate_user_password})
        resource.run_action(:run)
        expect(resource).not_to be_updated_by_last_action
      end

      it "causes the resource to be updated for not_if" do
        resource.not_if(guard_identity_command, {user: windows_alternate_user, password: windows_alternate_user_password})
        resource.run_action(:run)
        expect(resource).to be_updated_by_last_action
      end
    end
  end
end