require 'capistrano/helpers/aws_helper'
require 'capistrano/helpers/cap_helper'

def autoscale(*args)
  include Capistrano::DSL
  include AwsHelper
  include CapHelper
  invoke 'autoscaling_deploy:freeze_auto_scaling_group'
  ec2_instances = fetch_ec2_instances
  ec2_instances.each do |hostname|
    server(hostname, *args)
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
    invoke 'autoscaling_deploy:unfreeze_auto_scaling_group' if fetch(:aws_autoscaling_max_instances)
  end
end

namespace :autoscaling_deploy do
  include AwsHelper
  include CapHelper

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

  desc 'Unfreeze Auto Scaling Group.'
  task :unfreeze_auto_scaling_group do
    region = fetch(:aws_region)
    key = fetch(:aws_access_key_id)
    secret = fetch(:aws_secret_access_key)
    group_name = fetch(:aws_autoscaling_group_name)
    ip_type = fetch(:aws_ip_type)
    autoscaling_max_instances = fetch(:aws_autoscaling_max_instances)
    instance_type = fetch(:aws_instance_type)
    security_groups = fetch(:aws_security_groups)
    create_ami_image(region, key, secret, group_name, ip_type, instance_type, security_groups)
    puts 'Unfreeze Auto Scaling Group.'
    update_auto_scale_group(region, key, secret, group_name, ip_type, autoscaling_max_instances)
  end

  desc 'Add server from Auto Scaling Group.'
  task :setup_instances do
    ec2_instances = fetch_ec2_instances
    aws_deploy_roles = fetch(:aws_deploy_roles)
    aws_deploy_user = fetch(:aws_deploy_user)
    aws_ssh_key = fetch(:aws_ssh_key)
    ec2_instances.each {|instance|
      if ec2_instances.first == instance
        server instance, user: aws_deploy_user, roles: aws_deploy_roles, primary: true,
               ssh_options: {
                   keys: [aws_ssh_key],
                   forward_agent: true,
                   auth_methods: %w(publickey)
               }
        puts("First Server: #{instance} - #{aws_deploy_roles}")
      else
        server instance, user: aws_deploy_user, roles: sanitize_roles(aws_deploy_roles),
               ssh_options: {
                   keys: [aws_ssh_key],
                   forward_agent: true,
                   auth_methods: %w(publickey)
               }
        puts("Server: #{instance} - #{sanitize_roles(aws_deploy_roles)}")
      end
    }

  end

  def fetch_ec2_instances
    region = fetch(:aws_region)
    key = fetch(:aws_access_key_id)
    secret = fetch(:aws_secret_access_key)
    group_name = fetch(:aws_autoscaling_group_name)
    ip_type = fetch(:aws_ip_type)
    #update_auto_scale_group(region, key, secret, group_name, ip_type)
    instances = get_instances(region, key, secret, group_name, ip_type)

    puts("Found #{instances.count} servers (#{instances.join(',')}) for Auto Scaling Group: #{group_name} ")

    instances
  end

end