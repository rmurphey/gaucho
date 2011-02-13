# encoding: utf-8

require 'grit'
require 'fileutils'
require 'yaml'
require 'base64'
require 'unicode_utils'
require 'pp'

@titles = %w{Algid Factotum Jitney Sartorial Aestival Tripsis Gormless Anfractuous Lulliloo Ünîçòdé}
@alt_titles = %w{Discalceate Mimesis Pleonasm Bezoar Volacious Demiurgic}

@all_cats = %w(news projects articles)
@all_tags = %w(fun awesome cool lame bad sweet great weak zesty)

@all_more_toc = ['', "\n<!--more-->\n\n{{ toc }}\n", "\n<!--more-->\n"]

@all_authors = [nil, 'John Q. Public', 'John Q. Public <john@example.com>']

@all_dates = [nil, '2009-09-25 12:30:00 -0500']

@all_texts = [
  %Q{This text has **bold** and _italic_ text, some "quoted text that can't be beat," and look, [an external link](http://benalman.com) too!},
  'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Curabitur at erat id tellus rutrum cursus. Cras et elit est. Fusce id sapien nec dolor elementum tempus nec pulvinar diam. Sed euismod, sem ut luctus ullamcorper, nibh tellus volutpat felis, eget tempor quam sem a tortor. Nam tortor felis, mollis vitae vehicula non, consequat vel magna.',
  'Mauris suscipit cursus fringilla. Donec ut nisl quam, non blandit odio. Aenean quis est a massa iaculis ultricies. Nulla vel velit magna. Vivamus eget tortor ipsum, ac feugiat augue. Vivamus vel ipsum lorem.',
  'Praesent sapien massa, egestas venenatis tempor et, auctor ac libero. Duis a eleifend metus. Proin ultrices hendrerit rutrum. Curabitur id lorem eget nisi faucibus placerat. Vestibulum vitae nisl erat, quis elementum enim.',
  "* List item foo 1\n* List item bar 2\n* List item baz 3",
  "1. Ordered list item foo 1\n2. Ordered list item bar 2\n3. Ordered list item baz 3",
]

@all_incls = []
@all_incls = []
@all_incls << ['sample.rb', false, <<EOF
def wtf(x)
  if x < 17 && x > 5
    puts "yay, the < and > were escaped properly"
  end
end
EOF
]
@all_incls << ['awesome.js', false, <<EOF
function awesome() {
  console.log( 'OMG AWESOME!1' );
}
EOF
]
@all_incls << ['fancy.css', false, <<EOF
body.fancy {
  color: red;
  background: blue;
}
EOF
]
@all_incls << ['lolwat.html', false, <<EOF
<h1>LOL WAT</h1>
<h2>SUPER DUPER COOL</h2>
EOF
]
@all_incls << ['haiku.txt', false, <<EOF
this is a sample
text file with the answer to
the meaning of life
EOF
]
@all_incls << ['escaped_html.txt', false, <<EOF
<h2>ZOMG ESCAPED HTML</h2>
EOF
]
@all_incls << @hat = ['cowboy_hat.png', true, <<EOF
iVBORw0KGgoAAAANSUhEUgAAABAAAAAQCAYAAAAf8/9hAAAAGXRFWHRTb2Z0
d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAKJJREFUeNqkUsENgDAIFOLL
qbqAezhGx9A5XMAFXMcvetXEFkO1laQxAe64A0lEmj/BZsWT1BMc4K0fbxJ8
DULOsYNkWyeps3BFNw8FFiD9mgigBoeassKlS9O9HCfgOScZtbDcCMPNz2Bz
gnEVrZDwJ3pH4l3a+HYRv+AJtUnCfTsdehMFIenuzcZqLCCmJwSaJK/gBD8I
3ohiYJagJHYBBgAdlVsmfBCYiQAAAABJRU5ErkJggg==
EOF
]

@page_subdirs = ['yay/', 'nay/']
@file_subdirs = ['', 'zing/', 'zang/', 'zing/zong/']

@paths = {}

class String
  def transliterate
    UnicodeUtils.nfkd(self).gsub(/[^\x00-\x7F]/, '').to_s
  end
end

class Array
  def to_yaml_style
    :inline
  end
  
  # Shift `n` items off the front of the array and push them onto the end,
  # returning the items that were shift-pushed.
  def shift_rotate(n = nil)
    result = self.shift(n)
    self.push(*result)
    result
  end
  # Perform a shift_rotate on the passed-in `arr` array, then push the returned
  # results onto `self` and unique.
  def add_and_rotate(arr, n = nil)
    result = arr.shift_rotate(n)
    self.push(*result).uniq!
  end
end

def init_repo(path)
  @repo_path = File.expand_path(path)
  FileUtils.rm_rf(@repo_path)
  FileUtils.mkdir_p(@repo_path)
  FileUtils.cd(@repo_path)
  `git init .`
end

def article_title(title)
  "#{title} Article"
end

def article_path(title)
  article_title(title).transliterate.downcase.sub(' ', '-')
end

def read_index(title)
  path = article_path(title)
  docs = []
  File.open("#{path}/index.md") do |file|
    YAML.each_document(file) {|doc| docs << doc}
  end
  docs
end

def write_index(title, docs)
  path = article_path(title)
  # Since this script tries to simulate how user data will actually be stored,
  # ie. without extra quoting or \u-style escaping, and because .to_yaml escapes
  # unicode and quotes multi-line strings, YAML serialization is done manually.
  metas = []
  docs.first.each do |key, value|
    metas << if value.class == Array
      "#{key}: [#{value.join(', ')}]"
    else
      "#{key}: #{value}"
    end
  end
  index = metas.join("\n") + "\n--- |\n" + docs.last
  FileUtils.mkdir_p(path)
  File.open("#{path}/index.md", 'w') {|f| f.write(index)}
end

def write_incl(title, file = nil)
  path = article_path(title)
  file = @all_incls.shift_rotate(1)[0] if file.nil?
  subdir = @file_subdirs.shift_rotate(1)[0]
  FileUtils.mkdir_p("#{path}/#{subdir}")
  file_path = "#{path}/#{subdir}#{file[0]}"
  if file[1]
    File.open(file_path, 'wb') {|f| f.write(Base64.decode64(file[2]))}
  else
    File.open(file_path, 'w') {|f| f.write(file[2])}
  end
  "#{subdir}#{file[0]}"
end

def create_article(title)
  path = article_path(title)
  incl = write_incl(title, @hat)
  docs = []
  docs << meta = {
    'Title' => article_title(title),
    'subtitle' => "This is some stuff about #{title}.",
    'categories' => @all_cats.shift_rotate(1),
    'tags' => @all_tags.shift_rotate(2)
  }
  date = @all_dates.shift_rotate(1)[0]
  meta['date'] = date unless date.nil?
  author = @all_authors.shift_rotate(1)[0]
  meta['Author'] = author unless author.nil?
  docs << <<-EOF

This is a sample article about the word "[#{title}](/#{path}#arbitrary-hash)."

[{{ #{incl} }} Super Cowboy Hats!! {{ #{incl} }}]({{ #{incl} | url }})

#{@all_more_toc.shift_rotate(1)[0]}
  EOF
  docs
end

def commit_articles(commit_msg, added = false)
  puts commit_msg
  `git add .`
  `git commit -m "#{commit_msg}"`
  #sleep 0.1
end

init_repo('test_repo')

# create articles
@titles.each do |title|
  docs = create_article(title)
  write_index(title, docs)
  commit_articles("Added #{title} article.", true)
end

# modify tags, delete date, add text
@titles.each do |title|
  docs = read_index(title)
  docs[0]['tags'].add_and_rotate(@all_tags, 1)
  docs[0].delete('date')
  docs[1] += <<-EOF

## Sample header foo

#{@all_texts.shift_rotate(1).join}
  EOF

  write_index(title, docs)
  commit_articles("#{title}: added a tag and some content.")
end

# modify subtitle, add text
@titles.each do |title|
  docs = read_index(title)
  docs[0]['subtitle'].sub(/some stuff/, 'an article')
  docs[1] += <<-EOF

## Î'm lòvíñg "Çråzy" Üñîçòdé Hëàdérs!!?

#{@all_texts.shift_rotate(1).join}
  EOF

  write_index(title, docs)
  commit_articles("#{title}: tweaked subtitle, added more content.")
end

# change text
@titles.each do |title|
  docs = read_index(title)
  docs[1].gsub!(/\b(foo|bar|baz)\b/) do |word|
    "#{word.upcase}!"
  end

  write_index(title, docs)
  commit_articles("#{title}: uppercased a word (or three).")
end

# add content and a file
@titles.each do |title|
  docs = read_index(title)
  incl = write_incl(title)
  docs[1] += <<-EOF

### Including a file, a few different ways.

The file {{ #{incl} | link }}, included in its default format:

{{ #{incl} }}

And explicitly as text:

{{ #{incl} | text }}
  EOF

  write_index(title, docs)
  commit_articles("#{title}: included a file.")
end

# add a tag, two more files, committing articles in groups of 3
@titles_tmp = []
@titles.each_index do |i|
  title = @titles[i]
  @titles_tmp << title

  docs = read_index(title)
  docs[0]['tags'].add_and_rotate(@all_tags, 1)

  incl = write_incl(title)
  docs[1] += <<-EOF

### Including a second file:

{{ #{incl} }}
  EOF

  incl = write_incl(title)
  docs[1] += <<-EOF

### And a third file:

{{ #{incl} }}
  EOF

  write_index(title, docs)

  if (@titles.length - i - 1) % 3 == 0
    commit_articles("#{@titles_tmp.join(', ')}: included 2 files#{@titles_tmp.length > 1 ? ' (per article)' : ''}.")
    @titles_tmp = []
  end
end

# modify a few articles (uncommitted)
@titles[0..2].each do |title|
  docs = read_index(title)
  docs[0]['Title'] += '!!!'
  docs[1].gsub!(/(This is a sample article)/, '\1 with **LOCAL MODIFICATIONS**')

  write_index(title, docs)
end

# create an article (uncommitted)
@alt_titles[0..0].each do |title|
  docs = create_article(title)
  write_index(title, docs)
end

puts 'done!'
