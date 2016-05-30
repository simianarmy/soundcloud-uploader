#!/usr/local/bin/ruby
#
# Uploads audio file to soundcloud with a message
# Returns trackId on success, 0 on failure
#
# Usage: twhispr_upload.rb audio_path twitter_author
#
# Returns: Success: 1, Failure: 0
#
require 'soundcloud'

# Monkeypatch SoundCloud client to debug http
module SoundCloud
    class Client
        # Uncomment this to turn it on
        #debug_output $stderr
    end
end

class SoundCloudUploader
    def initialize(file, author)
        cnf = Psych.load_file(File.join(__dir__, 'config.yml'))

        @client = SoundCloud.new({
          :client_id     => cnf['client_id'],
          :client_secret => cnf['client_secret'],
          :username      => cnf['username'],
          :password      => cnf['password']
        })
        @id = File.basename(file, '.mp3')
        @file = file
        @author = author
        @title = make_title
    end

    # upload an audio file
    def upload
        # ensure it doesn't already exist
        if track = exists?
            return track.id
        end

        begin
            log "Uploading #{@file}..."
            track = @client.post('/tracks', :track => {
                :title => @title,
                :description => @id,
                :asset_data => File.new(@file, 'rb'),
                :tag_list => [@id, @author].join(' ')
                #:shared_to    => {
                #    :connections => [{:id => twitter_connection.id}]
                #}
            })
        rescue SoundCloud::ResponseError => err
            # 504 on upload means it was uploaded but we don't have a track id
            # If it was uploaded, it will be in the global playlist
            if err.message =~ /504/
                log "Got 504 - looking for #{@title} in global playlist."
                track = search_track_by_title(@client.get("/me/tracks"), @title)
            else
                raise err
            end
        end

        raise "No track object returned!" unless track
        log "uploaded track #{track.id}"

        add_to_playlist track.id

        # return track id
        track.id
    end

    def playlists(opts = {})
        # Caching - this is a huge payload
        @playlists ||= @client.get("/me/playlists", opts || {})
    end

    def exists?
        # fetch playlist by author
        return false unless plist = author_playlist

        # find track by title or tweet id in tags
        plist.tracks.find do |t|
            return t if t.title == @title

            t.tag_list.split.find do |tag|
                tag == @id
            end
        end
    end

    def log(msg)
        STDERR.puts msg
    end

    private

    def make_title
        [@author, @id].join('-')
    end
    
    def twitter_connection
        # get 'twitter' connection
        @client.get('/me/connections').find { |c| c.type == 'twitter' }
    end

    def add_to_playlist(track_id)
        unless playlist = author_playlist
            return create_playlist @author, [track_id]
        end

        log "updating playlist #{playlist.uri}..."

        track_ids = playlist.tracks.map(&:id)
        log "#{track_ids.count} tracks in playlist"

        begin
            # send update/put request to playlist
            track_ids << track_id
            @client.put(playlist.uri, :playlist => {
                :tracks => format_tracks_for_request(track_ids)
            })
        rescue SoundCloud::ResponseError => err
            log "SoundCloud Exception updating playlist! " + err.message

            # If playlist is too large for Soundcloud, start a new one
            if err.message =~ /422/ && track_ids.count >= 200
                create_playlist new_playlist_title(playlist), [track_id]
            end
        end
    end

    def author_playlist
        playlists(:q => @author).find_all { |pl|
            pl.title =~ /^#{@author}/
        }
        .sort_by(&:title)
        .last
    end

    def search_track_by_title(tracks, title)
        tracks.find { |t| t.title == title }
    end

    # create new playlist from tracklist
    def create_playlist(title, track_ids)
        log "Creating new playlist #{title}..."

        begin
            @client.post('/playlists', :playlist => {
                :title => title,
                :sharing => 'public',
                :tracks => format_tracks_for_request(track_ids)
            })
        rescue SoundCloud::ResponseError => err
            log "SoundCloud Exception creating playlist! " + err.message
            raise(err) # this is a fatal error
        end
    end

    def new_playlist_title(playlist)
        suffix = 2
        if matched = /#{@author}_(\d+)/.match(playlist.title)
            suffix = matched[1].to_i + 1
        end

        [@author, suffix].join('_')
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

choke "Need file path as 1st arg!" unless file = ARGV[0]
choke "Need author as 2nd arg!" unless author = ARGV[1]

status = 0
begin
    scup = SoundCloudUploader.new(file, author)
    # Debugging 502s from huge playlists payload
    #lists = scup.playlists
    #STDERR.puts "playlists returned"
    #choke lists.map(&:title).join(', ')
    track_id = scup.upload
    status = 1
    puts track_id # print to STDOUT for calling programs to read
rescue SoundCloud::ResponseError => err
    STDERR.puts "SoundCloud Exception uploading: #{file}: " + err.message
rescue
    STDERR.puts "Exception uploading: #{file}: " + $!.to_s
end

exit status 

