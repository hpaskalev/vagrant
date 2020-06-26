require "log4r"
require "vagrant/util/experimental"

module VagrantPlugins
  module ProviderVirtualBox
    module Cap
      module CleanupDisks
        LOGGER = Log4r::Logger.new("vagrant::plugins::virtualbox::cleanup_disks")

        # @param [Vagrant::Machine] machine
        # @param [VagrantPlugins::Kernel_V2::VagrantConfigDisk] defined_disks
        # @param [Hash] disk_meta_file - A hash of all the previously defined disks from the last configure_disk action
        def self.cleanup_disks(machine, defined_disks, disk_meta_file)
          return if disk_meta_file.values.flatten.empty?

          return if !Vagrant::Util::Experimental.feature_enabled?("disks")

          handle_cleanup_disk(machine, defined_disks, disk_meta_file["disk"])
          handle_cleanup_dvd(machine, defined_disks, disk_meta_file["dvd"])
          # TODO: Floppy disks
        end

        protected

        # @param [Vagrant::Machine] machine
        # @param [VagrantPlugins::Kernel_V2::VagrantConfigDisk] defined_disks
        # @param [Hash] disk_meta - A hash of all the previously defined disks from the last configure_disk action
        def self.handle_cleanup_disk(machine, defined_disks, disk_meta)
          storage_controllers = machine.provider.driver.read_storage_controllers
          primary_controller = storage_controllers.get_primary_controller

          primary = primary_controller.get_attachment(port: "0", device: "0")
          if !primary
            raise Vagrant::Errors::VirtualBoxDisksPrimaryNotFound
          end
          primary_uuid = primary[:uuid]

          if disk_meta
            disk_meta.each do |d|
              dsk = defined_disks.select { |dk| dk.name == d["name"] }
              if !dsk.empty? || d["uuid"] == primary_uuid
                next
              else
                LOGGER.warn("Found disk not in Vagrantfile config: '#{d["name"]}'. Removing disk from guest #{machine.name}")
                machine.ui.warn(I18n.t("vagrant.cap.cleanup_disks.disk_cleanup", name: d["name"]), prefix: true)

                controller = storage_controllers.get_controller!(name: d["controller"])
                attachment = controller.get_attachment(uuid: d["uuid"])

                if !attachment
                  LOGGER.warn("Disk '#{d["name"]}' not attached to guest, but still exists.")
                else
                  machine.provider.driver.remove_disk(controller.name, attachment[:port], attachment[:device])
                end

                machine.provider.driver.close_medium(d["uuid"])
              end
            end
          end
        end

        # @param [Vagrant::Machine] machine
        # @param [VagrantPlugins::Kernel_V2::VagrantConfigDisk] defined_dvds
        # @param [Hash] dvd_meta - A hash of all the previously defined dvds from the last configure_disk action
        def self.handle_cleanup_dvd(machine, defined_dvds, dvd_meta)
          if dvd_meta
            dvd_meta.each do |d|
              dsk = defined_dvds.select { |dk| dk.name == d["name"] }
              if !dsk.empty?
                next
              else
                LOGGER.warn("Found dvd not in Vagrantfile config: '#{d["name"]}'. Removing dvd from guest #{machine.name}")
                machine.ui.warn("DVD '#{d["name"]}' no longer exists in Vagrant config. Removing medium from guest...", prefix: true)

                storage_controllers = machine.provider.driver.read_storage_controllers
                controller = storage_controllers.get_controller!(name: d["controller"])
                attachment = controller.get_attachment(uuid: d["uuid"])

                if !attachment
                  LOGGER.warn("DVD '#{d["name"]}' not attached to guest, but still exists.")
                else
                  machine.provider.driver.remove_disk(controller.name, attachment[:port], attachment[:device])
                end
              end
            end
          end
        end
      end
    end
  end
end
