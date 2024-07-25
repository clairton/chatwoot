class Whatsapp::OneoffUnoapiCampaignService
  pattr_initialize [:campaign!]

  def perform
    raise "Invalid campaign #{campaign.id}" if inbox.inbox_type != 'Whatsapp' || channel.provider != 'unoapi' || !campaign.one_off?
    raise 'Completed Campaign' if campaign.completed?

    # marks campaign completed so that other jobs won't pick it up
    campaign.completed!

    process_audience(campaign.audience)
  end

  private

  delegate :inbox, to: :campaign
  delegate :channel, to: :inbox

  def process_audience(audience)
    interval = 0.seconds
    audience.each do |a|
      interval += rand(1..10).seconds
      CampaignMessageJob.set(wait_until: DateTime.current + interval.seconds).perform_later(
        campaign.account_id,
        campaign.inbox_id,
        campaign.message,
        a.symbolize_keys
      )
    end
  end
end
