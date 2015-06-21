require 'rubygems'
require 'twilio-ruby'
require 'sinatra/activerecord'
require_relative '../models/user'           #add the user model
require 'sidekiq'

require_relative '../sprint'
require_relative '../helpers'


SPRINT_NAME = "Sprint Spectrum, L.P."

FIRST = "FIRST"

FIRST_MMS = ["http://i.imgur.com/lLdB2zl.jpg", "http://i.imgur.com/msiTUwK.jpg"]


FIRST_SMS = "StoryTime: Enjoy your first story about Brandon!"


SAMPLE_SMS = "In class, we talked about our favorite recess games. The kids all loved racing. Keep learning with this story!\n-Ms. Wilson\n\nThanks for trying out StoryTime!"


EXAMPLE_SMS = "Thanks for trying out StoryTime, free rhyming stories by text! Enjoy your sample story about Brandon the Runner!"


SAMPLE = "SAMPLE"

EXAMPLE = "EXAMPLE"

PRO = "production"


class FirstTextWorker
  include Sidekiq::Worker

  sidekiq_options :queue => :critical

  sidekiq_options retry: false

  def perform(mode, type, phoneNum) #Send the User the first poem shortly after first signup
                              #if SAMPLE, send the text first and a different message
  	
    @user = User.find_by(phone: phoneNum)

    #set TWILIO credentials:
    account_sid = ENV['TW_ACCOUNT_SID']
    auth_token = ENV['TW_AUTH_TOKEN']

    @client = Twilio::REST::Client.new account_sid, auth_token

    if mode == PRO

      if type == FIRST
        Helpers.new_mms(FIRST_SMS, FIRST_MMS, @user.phone)
      elsif type == SAMPLE
        Helpers.new_mms(SAMPLE_SMS, FIRST_MMS, @user.phone)
      else
        Helpers.new_mms(EXAMPLE_SMS, FIRST_MMS, @user.phone)
      end

    else

      if type == FIRST
        Helpers.test_new_mms(FIRST_SMS, FIRST_MMS, @user.phone)
      elsif type == SAMPLE
        Helpers.test_new_mms(SAMPLE_SMS, FIRST_MMS, @user.phone)
      else
        Helpers.test_new_mms(EXAMPLE_SMS, FIRST_MMS, @user.phone)
      end

    end

    puts "Sent Very First Story message to" + @user.phone + "\n\n"

  end

end
