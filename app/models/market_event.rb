class MarketEvent < ApplicationRecord
  include Announceable
  include Insightful

  has_many :news_items, foreign_key: :market_event_id, dependent: :nullify

  validates :title,      presence: true
  validates :event_date, presence: true
  validates :kind,       presence: true, inclusion: { in: %w[market] }
  validates :status,     presence: true, inclusion: { in: %w[draft published] }
  # Anchored at both ends with \z (not \Z) and \S so a newline can't smuggle
  # content past the scheme check — a value like "https://ok\njavascript:…".
  validates :source_url, format: { with: /\Ahttps?:\/\/\S+\z/i, message: "must be an http(s) URL" },
                         allow_blank: true

  scope :chronological, -> { order(event_date: :asc) }
  # Title breaks a same-date tie so the order is total, not DB-dependent: the
  # events timeline paginates on this, and an unstable tie could show the same
  # event on two pages or skip it entirely. Matches EventsHelper#events_by_year.
  scope :recent_first,  -> { order(event_date: :desc, title: :desc) }
  scope :published,     -> { where(status: "published") }
  scope :drafts,        -> { where(status: "draft") }
end
