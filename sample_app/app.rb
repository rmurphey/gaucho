require 'sinatra'
require 'rack/cache'

require 'haml'
require 'mime/types'
require 'diffy'
require 'pygments'

require '../lib/gaucho'

require 'pp'
require 'awesome_print'

$cache_path = '/tmp/ba-cache'
FileUtils.rm_rf $cache_path
FileUtils.mkdir_p $cache_path

#def p(*args); nil; end

# Diffy limitation workaround (the inability to specify an actual diff)
module Diffy
  class Diff
    attr_writer :diff
  end
end

module Gaucho
  module Renderer
    # Flickr photo.
    def self.flickr(o)
      img = %Q{<img src="#{o.name}"/>}
      o.args ? %Q{<a href="http://www.flickr.com/photos/rj3/#{o.args}">#{img}</a>} : img
    end

    # Soundcloud player.
    def self.soundcloud(o)
      url = CGI::escape(o.name)
      unindent(<<-EOF)
      <object height="81" width="100%">
        <param name="movie" value="http://player.soundcloud.com/player.swf?url=#{url}&amp;show_comments=true&amp;auto_play=false&amp;color=ff7700"></param>
        <param name="allowscriptaccess" value="always"></param>
        <param name="wmode" value="window"></param>
        <embed wmode="window" allowscriptaccess="always" height="81" src="http://player.soundcloud.com/player.swf?url=#{url}&amp;show_comments=true&amp;auto_play=false&amp;color=ff7700" type="application/x-shockwave-flash" width="100%"></embed>
      </object>
      EOF
    end
  end

  class PageNotFound < Sinatra::NotFound
  end

  class FileNotFound < Sinatra::NotFound
    def initialize(name)
      #p "FileNotFound: #{name}"
    end
  end

  class App < Sinatra::Base
    #set :environment, :production
    p "Environment: #{settings.environment}"

    set :root, File.dirname(__FILE__)
    set :haml, format: :html5, attr_wrapper: '"'

    use Rack::Cache,
      :verbose => true,
      :metastore => "file:#{$cache_path}",
      :entitystore => "file:#{$cache_path}"

    check_fs_mods = development?
    renames = {
      'paean-article' => 'paean-article-new-url',
      'invidious-article' => 'invidious-article-new-url',
      'oscitate-article' => 'oscitate-article-new-url',
      'piste-article' => 'piste-article-new-url',
    }
    #$pageset = Gaucho::PageSet.new('../spec/test_repo/bare.git', renames: renames)
    #$pageset = Gaucho::PageSet.new('../spec/test_repo/small', check_fs_mods: check_fs_mods, renames: renames)
    #$pageset = Gaucho::PageSet.new('../spec/test_repo/huge', check_fs_mods: check_fs_mods, renames: renames)
    #$pageset = Gaucho::PageSet.new('../spec/test_repo/double', check_fs_mods: check_fs_mods, renames: renames, subdir: 'yay')
    #$pageset = Gaucho::PageSet.new('../spec/test_repo/double', check_fs_mods: check_fs_mods, renames: renames, subdir: 'nay')

    $pageset = Gaucho::PageSet.new('../../ba-import/new', check_fs_mods: check_fs_mods)

=begin
$pageset.pages.each do |page|
  if page.meta.tags.nil? || page.meta.tags.empty?
    puts page.id
    p page.meta.tags
  end
end
#ap $pageset
    p Renderer.filter_from_name('foo.txt')
    p Renderer.filter_from_name('foo.text')
    p Renderer.filter_from_name('foo.js')
    p Renderer.filter_from_name('foo.css')
    p Renderer.filter_from_name('foo.markdown')
    p Renderer.filter_from_name('foo.html')
    p Renderer.filter_from_name('foo.bar')
    pg = $pageset['unicode-article']
    p pg.title
    p '== files =='
    pg.files.each do |name, data|
      p [name, data.encoding.name, data.length, data.size, data.bytesize]
    end
    p '== commit =='
    pg.commits.last.files.each do |name, data|
      p [name, data.encoding.name, data.length, data.size, data.bytesize]
    end
    p $pageset.first.commit.diffs
    p $pageset.first.files
    p $pageset.subdir_path
    p $pageset.abs_subdir_path
    p $pageset.tree
    p $pageset.last
    p $pageset.length
    c = $pageset.first.commit
    p c.author.name
    p c.author.email
    p c.authored_date
    p c.committer.name
    p c.committer.email
    p c.committed_date
=end

    helpers do
      def date_format(date)
        ugly = date.strftime('%s')
        pretty = date.strftime('%b %e, %Y at %l:%M%P')
        %Q{<span data-date="#{ugly}">#{pretty}</span>}
      end
      def tag_url(tag)
        "/stuff-tagged-#{tag}"
      end
      def cat_url(cat)
        "/#{cat}-stuff"
      end
      # Render diffs for page revision history.
      def render_diff(diff)
        unless diff.binary?
          d = Diffy::Diff.new('', '')
          d.diff = diff.data
          d.to_s(:html)
        end
      end
    end

    before do
      cache_control :public, :max_age => 1000000 if production?
    end

    not_found do
      "<h1>OMG 404</h1>#{' '*512}"
    end

    # TODO: REMOVE?
    get '/rebuild' do
      $pageset.rebuild!
      redirect '/'
    end

    def tags(pages = @pages)
      tags = []
      tmp = {}
      pages.each {|p| p.tags.each {|t| tmp[t] ||= 0; tmp[t] += 1}}
      tmp.each {|t, n| tags << Gaucho::Config.new(tag: t, count: n)}
      min, max = tags.collect {|t| t.count}.minmax
      tags.sort! {|a, b| a.tag <=> b.tag}
      tags.each {|t| t.scale = [(200 * (t.count - min)) / (max - min), 100].max}
    end

    # INDEX
    get %r{^(?:/([0-9a-f]{7}))?/?$} do |sha|
      p ['index', params[:captures]]
      #start_time = Time.now
      @pages = $pageset.reset_shown
      @tags = tags
      @cats = @pages.collect {|c| c.categories}.flatten.uniq.sort
      #@pages = pages_categorized('music')
      @title = 'omg index'
      haml :index
    end

    # TAGS
    # /stuff-tagged-{tag}
    get %r{^/stuff-tagged-([-\w]+)} do |tag|
      p ['tag', params[:captures]]
      @pages = $pageset.reset_shown
      @pages.reject! {|p| p.tags.index(tag).nil?}.sort
      @title = %Q{Stuff tagged &ldquo;#{tag}&rdquo;}
      @tags = tags
      @cats = @pages.collect {|cat| cat.categories}.flatten.uniq.sort
      @index_back = true
      haml :index
    end

    # CATEGORIES
    # /{category}-stuff
    get %r{^/([-\w]+)-stuff$} do |cat|
      p ['cat', params[:captures]]
      @pages = $pageset.reset_shown
      @pages.reject! {|p| p.categories.index(cat).nil?}.sort
      pass if @pages.empty?
      @title = %Q{Stuff categorized &ldquo;#{cat}&rdquo;}
      @tags = tags
      @cats = [cat]
      @index_back = true
      haml :index
    end

=begin
    # RECENT CHANGES
    # /recent-changes
    get '/recent-changes' do
      p ['recent-changes']
      @pages = $all_pages
      @pages.each {|page| p page.commits.last.message}
      @tags = []
      @cats = []
      @index_back = true
      haml :index
    end
=end

    # DATE LISTING
    # /{YYYY}
    # /{YYYY}/{MM}
    # /{YYYY}/{MM}/{DD}
    get %r{^/(\d{4})(?:/(\d{2}))?(?:/(\d{2}))?/?$} do |year, month, day|
      p ['date', params[:captures]]
      date_arr = [year, month, day].compact
      @pages = $pageset.reset_shown.select {|page| page.date?(date_arr)}
      @title = %Q{Stuff dated &ldquo;#{date_arr.join('-')}&rdquo;}
      @tags = []
      @cats = []
      @index_back = true
      haml :index
    end

    # PAGE
    # /{name}
    # /{sha}/{name}
    # /{sha}/{name}/{file}
    # "name" can be (slashes are just replaced with dashes):
    #   name
    #   YYYY/name
    #   YYYY/MM/name
    #   YYYY/MM/DD/name
    get %r{^(?:/([0-9a-f]{7}))?/((?:\d{4}(?:/\d{2}){0,2}/)?[-\w]+)(?:/(.+))?$} do |sha, name, file|
      p ['page', params[:captures]]

      begin
        @page = $pageset[name]
        raise Sinatra::NotFound if @page.nil?
        if @page.class == String
          redirect @page, 302 # 301
          # cache?
          return #"redirect to #{@page}"
        end

        @page.shown = sha

        if sha && production?
          # cache heavily
        end

        if file
          content_type File.extname(file) rescue content_type :txt
          @page/file
        else
          @commit = @page.commit
          @commits = @page.commits
          @title = @page.title
          @content = @page.render #(nil, generate_toc: false)
          @index_back = true
          haml(@page.layout || :page)
        end
      #rescue
      #  raise Sinatra::NotFound
      end
    end
  end
end

if $0 == __FILE__
  Gaucho::App.run! :host => 'localhost', :port => 4567
end
