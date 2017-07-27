require 'capistrano/helpers/aws_helper'
require 'capistrano/helpers/cap_helper'

def autoscale
  include Capistrano::DSL
  include AwsHelper
  include CapHelper
  fetch(:aws_options).each do |options|
    ec2_instances = fetch_ec2_instances(options)
    ec2_instances.each_with_index do |hostname, i|
      roles = i==0 ? options[:aws_deploy_roles] : sanitize_roles(options[:aws_deploy_roles])
      server(hostname, user: options[:aws_deploy_user], roles: roles, ssh_options: { keys: [options[:aws_ssh_key]] })
    end
  end
end

namespace :load do
  task :defaults do
    set :aws_autoscaling, true
    set :aws_region, 'us-west-2'
    set :aws_deploy_roles, %w{web app db}
    set :aws_ip_type, 'public_dns_name'
  end
end

namespace :deploy do
  after 'deploy:finished', :check_autoscaling_hooks do
    #invoke 'autoscaling_deploy:unfreeze_auto_scaling_group'
  end
end

namespace :autoscaling_deploy do
  include AwsHelper
  include CapHelper

  desc 'Get list of runnin instances'
  task :list do
    aws_options = fetch(:aws_options)
    return if aws_options.nil?
    aws_options.each do |options|
      region = options[:aws_region]
      user = options[:aws_deploy_user]
      ssh_key = options[:aws_ssh_key]
      key = fetch(:aws_access_key_id)
      secret = fetch(:aws_secret_access_key)
      group_name = options[:aws_autoscaling_group_name]
      ec2_instances(region, key, secret, group_name).each do |instance|
        puts "#{get_name_from_tags(instance.tags)}:  ssh #{user}@#{instance.public_dns_name} -i #{ssh_key} "
      end
    end
  end

  desc 'Freeze Auto Scaling Group.'
  task :freeze_auto_scaling_group do
    region = fetch(:aws_region)
    key = fetch(:aws_access_key_id)
    secret = fetch(:aws_secret_access_key)
    group_name = fetch(:aws_autoscaling_group_name)
    ip_type = fetch(:aws_ip_type)
    puts 'Freeze Auto Scaling Group.'
    update_auto_scale_group(region, key, secret, group_name, ip_type)
  end

  desc 'Create AMI image for asg.'
  task :unfreeze_auto_scaling_group do
    aws_options = fetch(:aws_options)
    return if aws_options.nil?
    aws_options.each do |options|
      region = options[:aws_region]
      key = fetch(:aws_access_key_id)
      secret = fetch(:aws_secret_access_key)
      group_name = options[:aws_autoscaling_group_name]
      ip_type = options[:aws_ip_type]
      instance_type = options[:aws_instance_type]
      security_groups = options[:aws_security_groups]
      instance_name = options[:aws_instance_name]
      create_ami_image(region, key, secret, group_name, ip_type, instance_type, security_groups)

      set_instances_name(region, key, secret, group_name, instance_name)
      puts "Create AMI image for asg #{group_name}"
    end

    #autoscaling_max_instances = fetch(:aws_autoscaling_max_instances)
    #update_auto_scale_group(region, key, secret, group_name, ip_type, autoscaling_max_instances)
  end

  def fetch_ec2_instances(options = nil)
    region = options[:aws_region]
    key = fetch(:aws_access_key_id)
    secret = fetch(:aws_secret_access_key)
    group_name = options[:aws_autoscaling_group_name]
    ip_type = options[:aws_ip_type]
    #update_auto_scale_group(region, key, secret, group_name, ip_type)
    instances = get_instances(region, key, secret, group_name, ip_type)

    puts("Found #{instances.count} servers (#{instances.join(',')}) for Auto Scaling Group: #{group_name} ")

    instances
  end

end