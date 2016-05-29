#!/usr/local/bin/ruby
#
# Helper utilities to manage soundcloud tracks
#
# Usage: ??
#
require 'soundcloud'
require 'trollop'

# Monkeypatch SoundCloud client to debug http
module SoundCloud
    class Client
        # Uncomment this to turn it on
        # debug_output $stderr
    end
end

class SoundCloudAccount
    def initialize()
        cnf = Psych.load_file(File.join(__dir__, 'config.yml'))

        @client = SoundCloud.new({
          :client_id     => cnf['client_id'],
          :client_secret => cnf['client_secret'],
          :username      => cnf['username'],
          :password      => cnf['password']
        })
    end

    def playlist(pl)
        @client.get("/me/playlists/#{pl}")
    end

    def tracks
        @client.get("/me/tracks")
    end

    def exists?
        # fetch playlist by author
        return false unless plist = author_playlist

        # find track by tweet id in tags
        plist.tracks.find do |t|
            t.tag_list.split.find do |tag|
                tag == @id
            end
        end
    end

    def delete_track(id)
        @client.delete("/me/tracks/#{id}")
    end

    def dedupe_tracks(tracks)
        unique_titles = {}

        tracks.each do |t|
            unique_titles[t.title] ||= 0
            unique_titles[t.title] += 1
        end
        p "total tracks: #{tracks.size}"
        p "unique tracks: #{unique_titles.size}"

        unique_titles.select do |title, count|
            if count > 1
                p "dupe: #{title}"
                dupes = tracks.select { |t| t.title == title }
                dupes.shift # keep original track
                # delete the rest
                dupes.each do |dt|
                    p "deleting dupe track #{dt.id} - #{dt.title}"
                    delete_track(dt.id)
                end
            end
        end
    end

    def log(msg)
        STDERR.puts msg
    end

    private

    def author_playlist(author)
        playlists(:q => author).find_all { |pl|
            pl.title =~ /^#{author}/
        }
        .sort_by(&:title)
        .last
    end

    # @param {Array} tracks track ids
    # @return [{:id=>22448500}, {:id=>21928809}, {:id=>21778201}]
    def format_tracks_for_request(tracks)
        tracks.uniq.map{|id| {:id => id}} 
    end

end

def choke(s)
    STDERR.puts "FAIL: " + s
    exit 0
end

opts = Trollop::options do
    opt :v, "Verbose", :type => :bool
    opt :pl, "Playlist name", :type => :string        # string --name <s>, default nil
    opt :dedupe, "Delete duplicate tracks", :type => :bool
    opt :num_limbs, "Number of limbs", :default => 4  # integer --num-limbs <i>, default to 4
end

p opts

begin
    sc = SoundCloudAccount.new
    tracks = nil

    if opts[:pl]
        if pl = sc.playlist(opts[:pl])
            tracks = pl.tracks
        end
    end

    if opts[:dedupe]
        tracks ||= sc.tracks
        sc.dedupe_tracks(tracks)
    end
    #lists = scup.playlists
    #STDERR.puts "playlists returned"
    #choke lists.map(&:title).join(', ')
rescue SoundCloud::ResponseError => err
    STDERR.puts "SoundCloud Exception response: " + err.message
rescue
    STDERR.puts "Exception: " + $!.to_s
end


