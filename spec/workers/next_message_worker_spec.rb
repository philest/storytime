require_relative "../spec_helper"

require 'capybara/rspec'
require 'rack/test'
require 'timecop'

require 'time'
require 'active_support/all'

require_relative '../../helpers/twilio_helper'
require_relative '../../stories/story'
require_relative '../../stories/storySeries'

require_relative '../../workers/next_message_worker'

SLEEP_SCALE = 860

SLEEP_TIME = (1/ 8.0)



SPRINT_CARRIER = "Sprint Spectrum, L.P."

START_SMS_1 = "StoryTime: Welcome to StoryTime, free pre-k stories by text! You'll get "

START_SMS_2 = " stories/week-- the first is on the way!\n\nText " + HELP + " for help, or " + STOP + " to cancel."


MMS_ARR = ["http://i.imgur.com/CG1DxZd.jpg", "http://i.imgur.com/GEc0dhT.jpg"]

SMS = "This is a test SMS"

PHONE = "+15612125832"


#clean up leftover jobs
 Sidekiq::Worker.clear_all



describe 'The NextMessageWorker' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end


    before(:each) do
        NextMessageWorker.jobs.clear
        TwilioHelper.initialize_testing_vars
        Timecop.return
        TwilioHelper.testSleep
        User.create(phone: "+15612125832")
    end

    after(:each) do
      Timecop.return
    end


    it "properly adds jobs after calling NextMessageWorker" do
      expect(NextMessageWorker.jobs.size).to eq 0
      NextMessageWorker.perform_in(20.seconds, SMS, MMS_ARR, "+15612125832")
      expect(NextMessageWorker.jobs.size).to eq 1 
      puts "jobs: #{NextMessageWorker.jobs.size}"
    end

    it "has fullSend working even with mms_url in array" do
      @user = User.find_by_phone("+15612125832")
      arr = ["http://image.com"]
      TwilioHelper.fullSend(SMS, arr, @user.phone, "last")

      expect(TwilioHelper.getMMSarr).to eq arr
      expect(TwilioHelper.getSMSarr).to eq [SMS]
    end

    it "properly sends out a single MMS w/ SMS" do
      mms = ["http::image.com"] 
      NextMessageWorker.perform_in(20.seconds, SMS, mms, PHONE)
      expect(NextMessageWorker.jobs.size).to eq 1 
      NextMessageWorker.drain

      expect(TwilioHelper.getMMSarr).to eq mms
      expect(TwilioHelper.getSMSarr).to eq [SMS]
    end

    it "sends out a two MMS stack in the right order" do
      mms_arr = ["one", "two"]
      NextMessageWorker.perform_in(20.seconds, SMS, mms_arr, PHONE)
      puts "jobs: #{NextMessageWorker.jobs.size}"
      NextMessageWorker.drain
      
      # expect(NextMessageWorker.jobs.size).to eq 1
      # expect(TwilioHelper.getMMSarr).to eq ["one"]
      # expect(TwilioHelper.getSMSarr).to eq []
 
      NextMessageWorker.drain #the recursive call.
      expect(TwilioHelper.getMMSarr).to eq ["one", "two"]
      expect(TwilioHelper.getSMSarr).to eq [SMS]
      expect(NextMessageWorker.jobs.size).to eq 0

    end

    it "sends out a THREE MMS stack in the right order" do
      mms_arr = ["one", "two", 'three']
      NextMessageWorker.perform_in(20.seconds, SMS, mms_arr, PHONE)
      puts "jobs: #{NextMessageWorker.jobs.size}"
      NextMessageWorker.drain
      
      # expect(NextMessageWorker.jobs.size).to eq 1
      # expect(TwilioHelper.getMMSarr).to eq ["one"]
      # expect(TwilioHelper.getSMSarr).to eq []

      NextMessageWorker.drain #the recursive call.
      expect(TwilioHelper.getMMSarr).to eq ["one", "two", "three"]
      expect(TwilioHelper.getSMSarr).to eq [SMS]
      expect(NextMessageWorker.jobs.size).to eq 0
    end

    it "works for 21 users!" do 
      Timecop.travel(2015, 6, 22, 16, 24, 0) #on MONDAY!
      users = []

      TwilioHelper.testSleep #turn on

      (1..6).each do |number|
        get 'test/1561212582'+number.to_s+"/STORY/ATT"#each signs up
        user = User.find_by(phone: '1561212582'+number.to_s)

        NextMessageWorker.jobs.clear
        user.reload

        @@twiml_sms = []
        @@twiml_mms = []


        expect(user.total_messages).to eq(1)
        expect(user.story_number).to eq(0)


        users.push user

        @@twiml_sms = []
        @@twiml_mms = []
      end


      Timecop.travel(2015, 6, 23, 17, 24, 0) #on TUESDAY!
      Timecop.scale(SLEEP_SCALE) #1/8 seconds now are two minutes

      #WORKS WIHOUT SLEEPING!
      (1..10).each do 

          MainWorker.perform_async
          MainWorker.drain

        sleep SLEEP_TIME
      end


      expect(NextMessageWorker.jobs.size).to eq 6
      NextMessageWorker.drain #send all


      users.each do |user|
        user.reload

        expect(TwilioHelper.getMMSarr).to eq(Message.getMessageArray[0].getMmsArr)              
        expect(TwilioHelper.getSMSarr).to eq([Message.getMessageArray[0].getSMS])
        # expect(user.total_messages).to eq()
        expect(user.story_number).to eq(1)
        puts " "+ user.phone + "passed"
      end

    end



      



end
