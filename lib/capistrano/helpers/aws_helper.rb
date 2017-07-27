require 'aws-sdk'

module AwsHelper
  IP_TYPES = %w(public_ip_address public_dns_name private_ip_address private_dns_name)

  def get_name_from_tags(tags)
    tags.each do |tag|
      return tag.value if tag.key == 'Name'
    end
  end

  def ec2_instances(aws_region, aws_access_key_id, aws_secret_access_key, aws_autoscaling_group_name)
    aws_credentials = Aws::Credentials.new(aws_access_key_id, aws_secret_access_key)
    ec2 = Aws::EC2::Resource.new(region: aws_region, credentials: aws_credentials)
    instance_ids = fetch_autoscaling_group_instances(aws_region,  aws_autoscaling_group_name, aws_credentials)
    instance_ids.map do |instance, i|
      ec2.instance(instance.instance_id)
    end
  end


  def set_instances_name(aws_region, aws_access_key_id, aws_secret_access_key, aws_autoscaling_group_name, aws_instance_name)
    puts 'Setup names'
    name = "#{aws_autoscaling_group_name}-AMI-#{Time.now.to_i}"
    aws_credentials = Aws::Credentials.new(aws_access_key_id, aws_secret_access_key)
    ec2 = Aws::EC2::Resource.new(region: aws_region, credentials: aws_credentials)
    instance_ids = fetch_autoscaling_group_instances(aws_region,  aws_autoscaling_group_name, aws_credentials)
    instance_ids.each_with_index do |instance, i|
      name = "#{aws_instance_name} #{i}"
      ec2.instance(instance.instance_id).create_tags(tags: [{key: 'Name', value: name}])
    end
  end

  def create_ami_image(aws_region, aws_access_key_id, aws_secret_access_key, aws_autoscaling_group_name, aws_ip_type, aws_instance_type, aws_security_groups)
    puts 'Create AMI image'
    name = "#{aws_autoscaling_group_name}-AMI-#{Time.now.to_i}"
    aws_credentials = Aws::Credentials.new(aws_access_key_id, aws_secret_access_key)
    instance = fetch_autoscaling_group_instances(aws_region,  aws_autoscaling_group_name, aws_credentials).first
    return if instance.nil?
    ec2 = Aws::EC2::Client.new(region: aws_region, credentials: aws_credentials)

    old_images = ec2.describe_images(filters: [
        {
            name: 'tag:autoscaling_group_name',
            values: [aws_autoscaling_group_name],
        },
        {
            name: 'tag:application',
            values: ['rails'],
        }
    ])

    image = ec2.create_image({
                         description: name,
                         dry_run: false,
                         instance_id: instance.instance_id, # required
                         name: name, # required
                         no_reboot: true
                     })
    ec2.create_tags({resources: [image.image_id],
                     tags: [
                             {key: 'application', value: 'rails'},
                             {key: 'autoscaling_group_name', value: aws_autoscaling_group_name},
                           ]
                    })

    create_launch_configuration(aws_instance_type, aws_security_groups, image.image_id, aws_region, aws_autoscaling_group_name, aws_credentials )

    old_images.each do |image|

    end
  end

  def create_launch_configuration(aws_instance_type, aws_security_groups, image_id, aws_region, autoscaling_group_name, aws_credentials)
    name = "#{autoscaling_group_name}-LC-#{Time.now.to_i}"
    as = Aws::AutoScaling::Client.new(region: aws_region, credentials: aws_credentials)
    old_launch_configurations = as.describe_launch_configurations[0].select do |launch_configuration|
      launch_configuration.launch_configuration_name.include?("#{autoscaling_group_name}-LC")
    end
    as.create_launch_configuration({

                                      image_id: image_id,
                                      instance_type: aws_instance_type,
                                      launch_configuration_name: name,
                                      security_groups: aws_security_groups,
                                  })
    as.update_auto_scaling_group({
                                   auto_scaling_group_name: autoscaling_group_name,
                                   launch_configuration_name: name,
                               })
    old_launch_configurations.each do |launch_configuration|
      as.delete_launch_configuration({launch_configuration_name: launch_configuration.launch_configuration_name})
    end
  end

  def update_auto_scale_group(aws_region, aws_access_key_id, aws_secret_access_key, aws_autoscaling_group_name, aws_ip_type, max=nil)
    aws_credentials = Aws::Credentials.new(aws_access_key_id, aws_secret_access_key)
    count = max || get_instances(aws_region, aws_access_key_id, aws_secret_access_key, aws_autoscaling_group_name, aws_ip_type).count
    as = Aws::AutoScaling::Client.new(region: aws_region, credentials: aws_credentials)

    as.update_auto_scaling_group({
                                         auto_scaling_group_name: aws_autoscaling_group_name,
                                         max_size: p(count)
                                     })
  end

  def get_instances(aws_region, aws_access_key_id, aws_secret_access_key, aws_autoscaling_group_name, aws_ip_type)
    aws_credentials = Aws::Credentials.new(aws_access_key_id, aws_secret_access_key)
    retrieve_ec2_instances(aws_region, aws_autoscaling_group_name, aws_credentials, aws_ip_type)
  end

  private

  def retrieve_ec2_instances(aws_region, autoscaling_group_name, aws_credentials, aws_ip_type)
    instances = fetch_autoscaling_group_instances(aws_region, autoscaling_group_name, aws_credentials)

    if instances.empty?
      autoscaling_dns = []
    else
      instance_ids = instances.map(&:instance_id)
      ec2 = Aws::EC2::Resource.new(region: aws_region, credentials: aws_credentials)
      # info("Auto Scaling Group instances ids: #{instance_ids}")
      aws_ip_type = 'public_dns_name' unless IP_TYPES.include? aws_ip_type
        
      autoscaling_dns = instance_ids.map do |instance_id|
        ec2.instance(instance_id).send(aws_ip_type.to_sym)
      end
    end

    autoscaling_dns
  end

  def fetch_autoscaling_group_instances(aws_region, autoscaling_group_name, aws_credentials)
    as = Aws::AutoScaling::Client.new(region: aws_region, credentials: aws_credentials)
    as_groups = as.describe_auto_scaling_groups(
        auto_scaling_group_names: [autoscaling_group_name],
        max_records: 1,
    ).auto_scaling_groups

    # info("Auto Scaling Groups: #{as_groups}")

    as_group = as_groups[0]

    # info("Auto Scaling Group instances: #{as_group.instances}")

    as_group.instances
  end

end
