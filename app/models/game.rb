class Game < ActiveRecord::Base

  include Utilities

  has_many :checkouts
  has_many :setups
  has_many :teardowns

  belongs_to :title

  before_create :format_member_variables

  validates_format_of :barcode, with: Utilities.BARCODE_FORMAT
  validates :title, presence: true

  ST_LIMIT_COUNT = 150

  def format_member_variables
    self.barcode.upcase!
  end

  def self.get(barcode)
    # search for game based on barcode and event
    where(barcode: barcode.upcase, culled: false).first
  end

  def checked_in?
    self.checkouts.where(closed: false, event: Event.current).size == 0
  end

  def name
    self.title.title
  end

  def full_name
    "#{self.barcode} - #{self.name}"
  end

  def by
    self.title.publisher.name
  end

  def tourney?
    self.title.likely_tournament
  end

  def checked_out?
    self.checkouts.where(event: Event.current, closed: false).size > 0
  end

  def self.added_during_show
    where('games.created_at::date between ? and ?', Event.current.start_date, Event.current.end_date).includes(:title, title: :publisher).order('titles.title asc')
  end

  def self.culled_during_show
    where('culled = true and games.updated_at::date between ? and ?', Event.current.start_date, Event.current.end_date).includes(:title, title: :publisher).order('titles.title asc')
  end

  def self.search(search)
    search_tags = search.to_s.scan(/tag:([^\s]{1,})[\s]?/i).flatten
    search = search.gsub(/tag:([^\s]{1,})[\s]?/i, '').strip if search

    if Utilities.BARCODE_FORMAT.match(search)
      result = where(barcode: search.upcase)
    elsif search
      result = where(title: Title.search(search))
    else
      result = where(nil)
    end

    search_tags.each do |tag|
      case tag
        when /tournament/
          result = result.where(title: Title.where(likely_tournament: true))
        when /checkedout/
          result = result.where('games.id in (select distinct game_id from checkouts where closed = false)')
        else
          # do nothing
      end
    end

    result.where(culled: false)
  end

  def cull_game
    if self.checkouts.where(closed: false).size == 0
      self.update(culled: true)
      'Game successfully culled!'
    else
      'Game is still checked out! Please return game before culling it.'
    end
  end

  def info
    {
      name: self.name,
      publisher: self.by,
      barcode: self.barcode,
      likely_tournament: self.tourney?
    }
  end

  def self.generate(params)
    game = Game.new

    game.errors.add('title', 'Title can not be blank.') if params[:title].blank?
    game.errors.add('publisher', 'Publisher can not be blank.') if params[:publisher].blank?

    unless params[:title].blank? || params[:publisher].blank?
      title = Title.find_or_create_by(title: format(params[:title]), publisher: Publisher.find_or_create_by(name: format(params[:publisher])))
      params[:title] = title
      params.delete(:publisher)

      if !title.likely_tournament && params[:likely_tournament]
        title.update(likely_tournament: true)
      end

      params.delete(:likely_tournament)

      game.update(params)
    end

    game
  end

  def self.format(str)
    str.strip.split(' ').map(&:capitalize).join(' ')
  end

  def self.copies_as_csv
    csv = ["Title,Publisher,Barcode,LikelyTournament"]
    games = where(culled: false)
              .joins(:title, title: [:publisher])
              .select('initcap(titles.title) as name, initcap(publishers.name) as publisher, games.barcode, titles.likely_tournament')
              .order('lower(titles.title)').map do |db_row|
      "\"#{db_row[:name]}\",\"#{db_row[:publisher]}\",#{db_row[:barcode]},#{db_row[:likely_tournament]}"
    end

    csv.concat(games).join("\n")
  end

  def self.count_remaining_from(table)
    connection.execute(<<-SQL
        select count(*) as games_left from (#{sql_remaining_from(table)}) g
      SQL
    ).first['games_left'].to_i
  end

  def self.remaining_from(table)
    games_count = count_remaining_from(table)
    games_left = []
    if games_count <= ST_LIMIT_COUNT
      games_left = connection.execute(sql_remaining_from(table)).to_a
    end

    {
      games_count: games_count,
      games_left: games_left
    }
  end

  def self.sql_remaining_from(table)
    <<-SQL
      select g.barcode, initcap(lower(t.title)) as title, initcap(lower(p.name)) as publisher
      from games g
      inner join titles t on t.id = g.title_id
      inner join publishers p on p.id = t.publisher_id
      left join (select game_id from #{table} where event_id = #{Event.current.id}) st on st.game_id = g.id
      where
        g.culled = false
        and st.game_id is null
      order by 2, 1
    SQL
  end

  def self.missing_games
    events = Event.last_three_shows
    one_show = events.first
    two_show = events.second
    three_show = events.third

    connection.execute(<<-SQL
        select
          g.*, initcap(lower(t.title)) as title, initcap(lower(p.name)) as publisher
          from (
            select distinct
              g.barcode, g.title_id, g.created_at::date as created_at
              ,case when count(case when s.event_id = #{three_show.id} and s.game_id is not null then 1 end) > 0 then 'x' end as three_show_setup
              ,case when count(case when td.event_id = #{three_show.id} and td.game_id is not null then 1 end) > 0 then 'x' end as three_show_teardown
              ,case when count(case when s.event_id = #{two_show.id} and s.game_id is not null then 1 end) > 0 then 'x' end as two_show_setup
              ,case when count(case when td.event_id = #{two_show.id} and td.game_id is not null then 1 end) > 0 then 'x' end as two_show_teardown
              ,case when count(case when s.event_id = #{one_show.id} and s.game_id is not null then 1 end) > 0 then 'x' end as one_show_setup
              ,case when count(case when td.event_id = #{one_show.id} and td.game_id is not null then 1 end) > 0 then 'x' end as one_show_teardown
              ,count(distinct case when s.event_id between #{three_show.id} and #{one_show.id} and s.game_id is not null then s.event_id else null end) as setups
              ,count(distinct case when td.event_id between #{three_show.id} and #{one_show.id} and td.game_id is not null then td.event_id else null end) as teardowns
            from
              games g
            left join setups s on s.game_id = g.id
            left join teardowns td on td.game_id = g.id
            where
              g.culled = false
              and g.created_at::date <= '#{three_show.start_date}'
            group by 1, 2, 3
          ) g
          inner join titles t on t.id = g.title_id
          inner join publishers p on p.id = t.publisher_id
        where
          setups + teardowns < 4
          and (one_show_setup is null and one_show_teardown is null)
        order by lower(t.title), lower(p.name)
      SQL
    )
  end

end
