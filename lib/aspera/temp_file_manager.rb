require 'singleton'
require 'fileutils'
require 'etc'

module Aspera
  # create a temp file name for a given folder
  # files can be deleted on process exit by calling cleanup
  class TempFileManager
    SEC_IN_DAY=86400
    # assume no transfer last longer than this
    # (garbage collect file list which were not deleted after transfer)
    FILE_LIST_AGE_MAX_SEC=5*SEC_IN_DAY
    private_constant :SEC_IN_DAY,:FILE_LIST_AGE_MAX_SEC
    include Singleton
    def initialize
      @created_files=[]
    end

    # call this on process exit
    def cleanup
      @created_files.each do |filepath|
        File.delete(filepath) if File.file?(filepath)
      end
      @created_files=[]
    end

    # ensure that provided folder exists, or create it, generate a unique filename
    # @return path to that unique file
    def new_file_path_in_folder(temp_folder,add_base='')
      FileUtils.mkdir_p(temp_folder) unless Dir.exist?(temp_folder)
      new_file=File.join(temp_folder,add_base+SecureRandom.uuid)
      @created_files.push(new_file)
      return new_file
    end

    # same as above but in global temp folder
    def new_file_path_global(base_name)
      username = Etc.getlogin || Etc.getpwuid(Process.uid).name || 'unknown_user' rescue 'unknown_user'
      return new_file_path_in_folder(Etc.systmpdir,base_name+'_'+username+'_')
    end

    def cleanup_expired(temp_folder)
      # garbage collect undeleted files
      Dir.entries(temp_folder).each do |name|
        file_path=File.join(temp_folder,name)
        age_sec=(Time.now - File.stat(file_path).mtime).to_i
        # check age of file, delete too old
        if File.file?(file_path) and age_sec > FILE_LIST_AGE_MAX_SEC
          Log.log.debug("garbage collecting #{name}")
          File.delete(file_path)
        end
      end

    end
  end
end
