
require "optparse"
require "pathname"
require "fileutils"
require "erb"
require "yaml"

class CutAGemCommand
	VERSION = "0.0.8.3"

	include FileUtils
	def self.run(argv)
		new(argv.dup).run
	end

	def initialize(argv)
		@argv = argv

		@config = Pathname.new(ENV["HOME"]) + ".cutagem/config.yaml"
		@parser = OptionParser.new do |parser|
			parser.banner = <<-EOB.gsub(/^\t+/, "")
				Usage: #$0 [options] gemname
			EOB

			parser.separator ""
			parser.separator "Options:"

			parser.on("-s", "--select", "Select template interactively.") do |select|
				@select = select
			end

			parser.on("-d", "--desc", "Describe this gem.") do |description|
				@description = description
			end

			parser.on("-c", "--config", "Configure user values. Use $EDITOR") do |c|
				@config.parent.mkpath
				unless @config.exist?
					@config.open("w") do |f|
						f << <<-EOF.gsub(/^\t+/, "")
						author: "#{ENV['USER']}"
						email:  "#{ENV['USER']}@#{ENV['HOST']}"
						EOF
					end
				end
				exec(ENV["EDITOR"], @config.to_s)
			end

			parser.on("--copy-template NAME", "Copy template to user template dir naming NAME") do |name|
				path = Pathname.new(ENV["HOME"]) + ".cutagem/templates" + name
				if path.exist?
					puts "#{path} is already exists."
					exit 1
				end
				template = select_template(true)
				cp_r template, path, :verbose => true
				exit
			end

			parser.on('--gem-class GEMCLASS', 'Specify your gem class name explicitly') do |gemclass|
				@gemclass = gemclass
			end

			parser.on("--version", "Show version string `#{VERSION}'") do
				puts VERSION
				exit
			end
		end
	end

	def run
		@parser.order!(@argv)
		unless @argv.first
			puts "gemname must be required."
			exit 1
		end

		pwd = Pathname.pwd

		author      = self.author
		email       = self.email
		gemname     = @argv.shift
		gemid       = gemname.gsub("-", "")
		gempath     = gemname.gsub("-", "/")
		gemclass    = @gemclass ? @gemclass : gempath.split("/").map {|c|
			c.split(/_/).collect {|i| i.capitalize }.join("")
		}.join("::")
		description = @description

		template = select_template(@select)

		gemdir = pwd + gemname

		if gemdir.exist?
			puts "#{gemdir.basename} is already exists."
			exit
		end

		config = {}
		begin
			config = YAML.load(@config.read)
			author = config["author"] if config["author"]
			email  = config["email"]  if config["email"]
			puts "~/.cutagem/config.yaml is found. Use it."
		rescue Errno::ENOENT
			puts "~/.cutagem/config.yaml is not found. Use default."
		end

		begin
			cp_r template, gemdir, :verbose => true
			Pathname.glob(gemdir + "**/gemname*") do |f|
				new = f.parent + f.basename.to_s.sub(/gemname/, gemname)
				puts "Rename #{f.relative_path_from(gemdir)} to #{new.relative_path_from(gemdir)}"
				f.rename(new)
			end
			Pathname.glob(gemdir + "**/gempath*") do |f|
				new = f.parent + f.basename.to_s.sub(/gempath/, gempath)
				puts "Rename #{f.relative_path_from(gemdir)} to #{new.relative_path_from(gemdir)}"
				new.parent.mkpath
				f.rename(new)
			end
			Pathname.glob(gemdir + "**/*") do |f|
				next unless f.file?
				f.open("r+") do |f|
					content = f.read
					f.rewind
					f.puts ERB.new(content).result(binding)
					f.truncate(f.tell)
				end
			end
		rescue
			gemdir.rmtree
			raise
		end

		puts "Done."
		if ENV["EDITOR"]
			puts "Type any key to edit Rakefile."
			gets
			exec(ENV["EDITOR"], gemdir + "Rakefile")
		end
	end

	def author
		res = `git-config --global --get user.name 2> /dev/null`
		if $?.success?
			res.strip
		else
			ENV['USER']
		end
	end

	def email
		res = `git-config --global --get user.email 2> /dev/null`
		if $?.success?
			res.strip
		else
			"#{ENV['USER']}@#{ENV['HOST']}"
		end
	end

	# Select template from system templates and user templtes.
	# if +select+ is true, select templates interactively.
	def select_template(select)
		@templates = Pathname.new(File.dirname(__FILE__)).realpath + '../templates'
		@user_templates = Pathname.new(ENV["HOME"]).realpath + '.cutagem/templates'

		templates = []
		u_templates = []
		if @user_templates.exist?
			Pathname.glob(@user_templates + "*").each do |t|
				t = [".cutagem/templates/#{t.basename}", t]
				if t[1].basename.to_s == "default"
					u_templates.unshift(t)
				else
					u_templates << t
				end
			end
		end
		Pathname.glob(@templates + "*").each do |t|
			t = ["#{t.basename}", t]
			if t[1].basename.to_s == "default"
				templates.unshift(t)
			else
				templates << t
			end
		end
		templates = u_templates + templates

		if select
			puts "Select template:"
			templates.each_with_index do |item,index|
				puts "% 2d. %s" % [index+1, item.first]
			end
			input = gets.chomp
			case input
			when ""
				template = templates.first
			when /^\d+$/
				template = templates[input.to_i-1]
			else
				template = nil
				puts "Canceled"
				exit
			end
		else
			template = templates.first
		end
		unless template
			puts "Not select template."
			exit
		end
		puts "Using Template: %s" % template
		template[1]
	end
end
