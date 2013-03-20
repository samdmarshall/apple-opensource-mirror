#!/usr/bin/env ruby
require 'strscan'

# https://github.com/jordi/version_sorter/blob/master/version_sorter.rb
module VersionSorter
  extend self

  def sort(list)
    ss     = StringScanner.new ''
    pad_to = 0
    list.each { |li| pad_to = li.size if li.size > pad_to }

    list.sort_by do |li|
      ss.string = li
      parts     = ''

      begin
        if match = ss.scan_until(/\d+|[a-z]+/i)
          parts << match.rjust(pad_to)
        else
          break
        end
      end until ss.eos?

      parts
    end
  end

  def rsort(list)
    sort(list).reverse!
  end
end

include VersionSorter
projects = {}
Dir.entries("projects").each do | projectdir |
  next if projectdir == "." or projectdir == ".."
  projectname, projectversion = projectdir.split("-")
  if not projects[projectname]
    projects[projectname] = [ projectversion ]
  else
    projects[projectname].push(projectversion)
  end
end

basedir = Dir.pwd

if not ENV.include?('GITHUB_AUTH')
  puts "Error: define GITHUB_AUTH with GitHub username:password"
  exit 1
end

projects.keys.sort.each do | project | 
  Dir.chdir(basedir)
  versions = VersionSorter.sort(projects[project])
  gitdir = "gitify/#{project}"
  if not File.exists?(gitdir)
    Dir.mkdir(gitdir)
  end
  if not File.exists?("#{gitdir}/.git")
    puts `git init #{gitdir}`
  end

  versions.each do | version | 
    puts "PROJECT: #{project} VERSION: #{version}" 
    Dir.chdir(basedir)
    Dir.chdir(gitdir)
    json_file = "../../#{project}.github.json"
    if not File.size?(json_file)
      puts "Creating GitHub repo"
      system "curl -i -u #{ENV['GITHUB_AUTH']} https://api.github.com/orgs/aosm/repos -d '{\"name\":\"#{project}\"}' > #{json_file}"
    end
    if `git remote`.chomp.eql?("")
      puts "Adding remote"
      system "git remote add origin git@github.com:aosm/#{project}"
    end
    if not `git tag -l #{version}`.eql?("")
      puts "Version #{version} already imported to git"
      next
    end
    puts "Importing version #{version}"
    srcdir="#{basedir}/projects/#{project}-#{version}"
    xattrs=`xattr -l #{srcdir} | grep '^nu\.dll.aosm\.' | cut -f 1 -d :`.split(/[\r\n]+/)
    if not system "rsync -avz --delete --exclude=.git #{srcdir}/ ."
      puts "Error: failed to rsync #{project} version #{version}"
      exit 1
    end
    if not system "git add ."
      puts "Error: failed to add #{project} version #{version} to git"
      exit 1
    end
    if not system "git commit -am \"version #{version}\""
      puts "Error: failed to commit #{project} version #{version} to git"
      exit 1
    end    
    if not system "git tag #{version}"
      puts "Error: failed to tag #{project} version #{version}"
      exit 1
    end
    xattrs.each do | xattr |
      tag = xattr.sub("nu.dll.aosm.", "")
      if not system "git tag #{tag}" 
        puts "Error: failed to set release tag #{tag} for #{project} version #{version}"
        exit 1
      end
    end
  end
  tree_push_file = "../../#{project}-#{versions[-1]}.tree.pushed"
  tags_push_file = "../../#{project}-#{versions[-1]}.tags.pushed"
  if not File.exists?(tree_push_file)
    if system "git push --all -u origin"
      system "touch #{tree_push_file}"
    end
  end
  if not File.exists?(tags_push_file)
    if system "git push --tags"
      system "touch #{tags_push_file}"
    end
  end
end
