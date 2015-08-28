ENV['RACK_ENV'] = "test"

require_relative "./spec_helper"


require 'sinatra/r18n'

require 'capybara/rspec'
require 'rack/test'
require 'timecop'

require_relative '../constants'
require_relative '../sprint'
require_relative '../auto-signup'
#CONSTANTS

#NOTE: THE CARRIER PARAMA DOES NOTHING!!!! IT'S A HOAX

HELP_URL = "HELP%20NOW"
STOP_URL = "STOP%20NOW"
TEXT_URL = "TEXT"

SPRINT_QUERY_STRING = 'Sprint%20Spectrum%2C%20L%2EP%2E'


SINGLE_SPACE_LONG = ". If you can't receive picture msgs, reply TEXT for text-only stories.
Remember that looking at screens within two hours of bedtime can delay children's sleep and carry health risks, so read StoryTime earlier in the day.
Normal text rates may apply. For help or feedback, please contact our director, Phil, at 561-212-5831. Reply " + STOP + " to cancel."

NO_NEW_LINES = "If you can't receive picture msgs, reply TEXT for text-only stories. Remember that looking at screens within two hours of bedtime can delay children's sleep and carry health risks, so read StoryTime earlier in the day. Normal text rates may apply. For help or feedback, please contact our director, Phil, at 561-212-5831. Reply " + STOP + " to cancel."

SMALL_NO_NEW_LINES = "If you can't receive picture msgs, reply TEXT for text-only stories. Remember that looking at screens within two hours of bedtime can delay children's sleep and carry health risks, so read StoryTime earlier in the day."

MIX = "If you can't receive picture msgs, reply TEXT for text-only stories. Remember that looking at screens within two hours of bedtime can delay children's sleep and carry health risks, so read StoryTime earlier in the day. Normal text rates may apply. For help or feedback, please contact our director, Phil, at 561-212-5831.\nReply " + STOP + " to cancel."

MIXIER = "If you can't receive picture msgs, reply TEXT for text-only stories.\nRemember that looking at screens within two hours of bedtime can delay children's sleep and carry health risks, so read StoryTime earlier in the day. Normal text rates may apply. For help or feedback, please contact our director, Phil, at 561-212-5831.\nReply " + STOP + " to cancel."


  DEFAULT_TIME = Time.new(2015, 6, 21, 17, 30, 0, "-04:00").utc #Default Time: 17:30:00 (5:30PM), EST


include Text


describe 'The StoryTime App' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end


    before(:each) do
      Helpers.initialize_testing_vars
      FirstTextWorker.jobs.clear
      NextMessageWorker.jobs.clear
      NewTextWorker.jobs.clear
      Sidekiq::Worker.clear_all
    end

    after(:each) do
      Sidekiq::Worker.clear_all
    end


  it "routes successfully home" do
    get '/'
    expect(last_response).to be_ok
  end

  # SMS TESTS
  it "isn't there before" do
  	  expect(User.find_by_phone("555")).not_to eq("555")
  end

  it "signs up" do
  	get '/test/555/STORY/ATT'
    @user = User.find_by_phone("555")
    @user.reload
  	expect(@user.phone).to eq("555")
  end


  it "signs up different numbers" do
  	get '/test/888/STORY/ATT'
    @user = User.find_by_phone("888")
    @user.reload
  	expect(@user.phone).to eq("888")
  end

  it "sends correct sign up sms" do
  	get '/test/999/STORY/ATT' 
  	expect(Helpers.getSMSarr[0]).to eq(Text::START_SMS_1 + 2.to_s + Text::START_SMS_2)
  end

  it "sends correct sign up sms" do
    get '/test/999/STORY/ATT' 

  end

  it "sends new text properly using integration testing w/ credentials" do

    Helpers.smsSend("Your Test Cred worked!", "+15612125831", "normal")

  end



  it "sends correct sign up sms to Sprint users" do
    get '/test/998/STORY/' + SPRINT_QUERY_STRING
    expect(Helpers.getSMSarr[0]).to eq(Text::START_SPRINT_1 + "2" + Text::START_SPRINT_2)
  end

  describe "User" do

  	before(:each) do
 	 	  @user = User.create(phone: "444", time: DEFAULT_TIME)
  	end

      	it "has nil child birthdate value" do
      		expect(@user.child_birthdate).to eq(nil)
      	end

        it "has proper default age of 4" do
           expect(@user.child_age).to eq(4)
        end

        it "has proper default time" do
           expect(@user.time).to eq(DEFAULT_TIME)
        end

        it "has default time of 5:30" do
           expect(@user.time.hour).to eq(21)
           expect(@user.time.min).to eq(30)
           expect(@user.time.zone).to eq("UTC")

        end  

  end 


#HELP TESTS
  describe "Help tests" do
    before(:each) do
      @user = User.create(phone: "400")
    end




    #last time test
    it "registers default time well" do 
      get '/test/898/STORY/ATT'
      @user = User.find_by(phone: 898)
      @user.reload
      expect(@user.time.hour).to eq(DEFAULT_TIME.utc.hour)
      expect(@user.time.min).to eq(DEFAULT_TIME.utc.min)
    end



    it "responds to HELP NOW" do
      get "/test/400/" + HELP_URL + "/ATT"
      @user.reload
      expect(Helpers.getSimpleSMS).to eq(Text::HELP_SMS_1 + "Tues/Thurs" + Text::HELP_SMS_2)
    end

    it "responds to 'help now' (non-sprint)" do
      get "/test/400/help%20now/ATT"
      expect(Helpers.getSimpleSMS).to eq(Text::HELP_SMS_1 + "Tues/Thurs" + Text::HELP_SMS_2)
    end


    describe "sub test" do
      before(:each) do
        @user.update(carrier: "Sprint Spectrum, L.P.")
      end

        it "responds to HELP NOW from sprint" do
          get "/test/400/HELP%20NOW/" + SPRINT_QUERY_STRING
          expect(Helpers.getSimpleSMS).to eq(Text::HELP_SPRINT_1 + "Tue/Th" + Text::HELP_SPRINT_2)
      end

    end

  end


#BIRTHDAY REGISTRATION
  # describe "BIRTHDATE tests" do
  #   before(:each) do
  #     @user = User.create(phone: "500", set_birthdate: false) #have just received third story
  #   end

  #   it "should not register invalid birthdate" do
  #     get '/test/500/0912555/ATT'
  #     expect(Helpers.getSimpleSMS).to eq(WRONG_BDAY_FORMAT)
  #   end

  #   it "registers a custom birthdate" do
  #     get '/test/500/0911/ATT'
  #    TIME_SMS = "StoryTime: Great! Your child's birthdate is " + "09" + "/" + "11" + ". If not correct, reply REDO. If correct, enjoy your next age-appropriate story!"
  #     expect(Helpers.getSimpleSMS).to eq(TIME_SMS)
  #   end

  #   it "correctly updates age" do
  #     get '/test/500/0911/ATT'
  #     @user.reload
  #     expect(@user.child_age).to eq(3)
  #   end



  #   it "too young shouldn't be allowed in" do
  #      get '/test/500/0914/ATT'
  #     expect(Helpers.getSimpleSMS).to eq(TOO_YOUNG_SMS)
  #   end


  #   it "keeps birthdate for too young" do
  #      get '/test/500/0914/ATT'
  #      @user.reload
  #     expect(@user.child_birthdate).to eq("0914")
  #   end



  #   describe "further Bday" do
  #     before(:each) do
  #     @user.update(set_birthdate: true) #have just received third story
  #   end

  #     it "shouldn't register a birthday after it's been set" do
  #       get '/test/500/0911/ATT'
  #      TIME_SMS = "StoryTime: Great! Your child's birthdate is " + "09" + "/" + "11" + ". If not correct, reply STORY. If correct, enjoy your next age-appropriate story!"
  #       expect(Helpers.getSimpleSMS).not_to eq(TIME_SMS)
  #     end

  #   end

  # end


  #   describe "TIME tests" do
  #   before(:each) do
  #     @user = User.create(phone: "600", set_time: false) #have just received first two stories
  #   end

  #     it "registers a custom time" do
  #       get '/test/600/6:00pm/ATT'
  #       @user.reload
  #       expect(Helpers.getSimpleSMS).to eq("StoryTime: Sounds good! Your new story time is #{@user.time}. Enjoy!")
  #     end

  #     it "registers a custom time in spaced format" do
  #       get '/test/600/6:00%20pm/ATT'
  #       @user.reload
  #       expect(Helpers.getSimpleSMS).to eq("StoryTime: Sounds good! Your new story time is #{@user.time}. Enjoy!")
  #     end

  #     describe "further time tests" do
  #       before(:each) do
  #       @user.update(set_time: true) #have just received third story
  #     end

  #     it "shouldn't register a time after it's been set" do
  #       get '/test/600/6:00pm/ATT'
  #       expect(Helpers.getSimpleSMS).to eq(Text::NO_OPTION)
  #     end

  #   end



    describe "Series" do
      before(:each) do
        @user = User.create(phone: "700", story_number: 3, awaiting_choice: true, series_number: 0)
      end

    it "updates series_choice" do
      get '/test/700/p/ATT'
      @user.reload
      expect(@user.series_choice).to eq("p")
    end

    it "good text response" do
      get '/test/700/p/ATT'
      @user.reload
      expect(Helpers.getSimpleSMS).to_not eq(Text::BAD_CHOICE)
    end

    it "doesn't register a letter weird choice" do
      get '/test/700/X/ATT'
      @user.reload
      expect(Helpers.getSimpleSMS).to eq(Text::BAD_CHOICE)
    end

    it "doesn't register a letter on a diff day" do
      @user.update(series_number: 1)
      @user.reload
      get '/test/700/p/ATT'
      @user.reload
      expect(Helpers.getSimpleSMS).to eq(Text::BAD_CHOICE)
    end


    it "works for uppercase" do
      get '/test/700/P/ATT'
      @user.reload
      expect(Helpers.getSimpleSMS).to_not eq(Text::BAD_CHOICE)
    end


    it "updates awaiting choice" do
      get '/test/700/P/ATT'
      @user.reload
      expect(@user.awaiting_choice).to eq(false)
    end


    it "updates awaiting choice" do
      @user.update(awaiting_choice: false)
      @user.reload
      get '/test/700/p/ATT'
      @user.reload
      expect(Helpers.getSimpleSMS).to eq(Text::NO_OPTION)
    end


  end




      describe "STOP NOW works" do

        it "properly unsubscribes" do
          @user = User.create(phone: "5555", story_number: 0, subscribed: true)

          get '/test/5555/' + STOP_URL + "/ATT"
          @user.reload
          expect(@user.subscribed).to eq(false)
        end


        it "properly resubscribes" do
          @user = User.create(phone: "5555", story_number: 0, subscribed: true)

          get '/test/5555/' + STOP_URL + "/ATT"
          @user.reload
          get '/test/5555/STORY/ATT'
          @user.reload
          expect(@user.subscribed).to eq(true)
        end

        it "send good resubscription msg" do
       @user = User.create(phone: "666")


          get "/test/666/" + STOP_URL + "/ATT"
          @user.reload


          get '/test/666/STORY/ATT'
          @user.reload
          expect(Helpers.getSimpleSMS).to eq(Text::RESUBSCRIBE_LONG)
        end


        #SPRINT tests

        it "leaves a message intact if under 160" do
          expect(Sprint.chop(Text::STOPSMS)).to eq([Text::STOPSMS])
        end

        it "seperates a longer message into two texts" do
          expect(Sprint.chop(Text::BAD_TIME_SMS).length).to eq(2)
          puts Sprint.chop(Text::BAD_TIME_SMS)
        end

        it "works for a long guy" do 
            puts Sprint.chop(Text::HELP_SMS_2)
        end

        it "works for single space long" do
            puts "\n"
            puts Sprint.chop(SINGLE_SPACE_LONG)
        end

        it "properly breaks up a 160+ chunk without newlines" do
            puts "\n"
            puts "\n"
            puts Sprint.chop(NO_NEW_LINES)
        end


        it "properly breaks up a MIX chunk without newlines" do
            puts "\n"
            puts "\n"
            puts Sprint.chop(MIX)
        end


        it "properly breaks up a MIXIER chunk without newlines" do
            puts "\n"
            puts "\n"
            puts Sprint.chop(MIXIER)
        end

      #SPRINT ACTION TESTS

        it "properly sends this as a three piece text to SPRINT" do
            @user = User.create(phone: "+15615422027", carrier: "Sprint Spectrum, L.P.")
            puts "\n"
            puts "\n"
            

            Helpers.text(SINGLE_SPACE_LONG, SINGLE_SPACE_LONG, @user.phone)


            expect(Helpers.getSMSarr.length).to eq(3)
            puts Helpers.getSMSarr
      end

        it "properly sends long poemSMS to Sprint users as many pieces" do
          @user = User.create( phone: "+5615422025", carrier: "Sprint Spectrum, L.P.")
            puts "\n"
            puts "\n"

            require_relative '../message'
            require_relative '../messageSeries'

            messageSeriesHash = MessageSeries.getMessageSeriesHash
            story = messageSeriesHash["p"+ @user.series_number.to_s][0]

            Helpers.text(story.getPoemSMS, story.getPoemSMS, @user.phone)

            expect(Helpers.getSMSarr.length).to_not eq(1)
            puts Helpers.getSMSarr
        end


  end


    describe "Full Respond Helper" do

      before(:each) do
        User.create(phone: "+15612125833", carrier: "ATT")
        @user = User.find_by_phone "+15612125833"
      end

      it "properly fullResponds" do
        @user.reload

        Helpers.fullRespond("Here's the SMS part!", ["imgur:://http: IMAGE 1"], "last")
        expect(Helpers.getSMSarr).to eq ["Here's the SMS part!"]
        expect(Helpers.getMMSarr).to eq ["imgur:://http: IMAGE 1"]

        puts Helpers.getSMSarr
        puts Helpers.getMMSarr

      end

      it "properly responds through wrapper (fullrespond)" do
        Helpers.text_and_mms("BODY!", "imgur:://http lastest Image", "+15612125833")

        expect(Helpers.getSMSarr).to eq ["BODY!"]
        expect(Helpers.getMMSarr).to eq ["imgur:://http lastest Image"]

        puts Helpers.getSMSarr
        puts Helpers.getMMSarr

      end


    end







    describe "the BREAK command" do

      before(:each) do
        Timecop.travel(2015, 6, 22, 16, 24, 0) #on MONDAY!
        User.create(phone: "+15612125833", carrier: "ATT")
        @user = User.find_by_phone "+15612125833"
      end

      it "won't send you a story that week if you're on break" do
        @user.reload
        expect(@user.subscribed).to eq true
        get '/test/+15612125833/'+Text::BREAK+"/ATT"

        expect(Helpers.getSMSarr).to include(Text::START_BREAK)


        Timecop.travel(2015, 6, 23, 17, 30, 0) #on Tuesday!

        SomeWorker.perform_async
        SomeWorker.drain

        NextMessageWorker.drain


        expect(Helpers.getMMSarr).to be_empty
        expect(Helpers.getSMSarr[1..-1]).to be_empty

        Timecop.travel(2015, 6, 25, 17, 30, 0) #on Thurs!

        SomeWorker.perform_async
        SomeWorker.drain

        NextMessageWorker.drain


        expect(Helpers.getMMSarr).to be_empty
        expect(Helpers.getSMSarr[1..-1]).to be_empty

      end


      it "won't send you a story the next week if you're on break" do
        @user.reload
        expect(@user.subscribed).to eq true
        get '/test/+15612125833/'+Text::BREAK+"/ATT"

        Timecop.travel(2015, 6, 30, 17, 30, 0) #on next Tuesday!

        SomeWorker.perform_async
        SomeWorker.drain

        NextMessageWorker.drain

        expect(Helpers.getMMSarr).to be_empty
        expect(Helpers.getSMSarr[1..-1]).to be_empty

        Timecop.travel(2015, 7, 2, 17, 30, 0) #on next Thurs!

        SomeWorker.perform_async
        SomeWorker.drain

        NextMessageWorker.drain

        expect(Helpers.getMMSarr).to be_empty
        expect(Helpers.getSMSarr[1..-1]).to be_empty

      end

      it "WILL send you a story the third week AFTER break" do
        @user.reload
        expect(@user.subscribed).to eq true
        Timecop.travel(2015, 6, 22, 16, 24, 0) #on MONDAY!

        get '/test/+15612125833/'+Text::BREAK+"/ATT"

        Timecop.travel(2015, 6, 23, 17, 30, 0) #on that Tuesday!
      
        SomeWorker.perform_async
        SomeWorker.drain

        NextMessageWorker.drain

        expect(Helpers.getMMSarr).to be_empty
        expect(Helpers.getSMSarr[1..-1]).to be_empty

        Timecop.travel(2015, 6, 25, 17, 30, 0) #on that Thursday!
      
        SomeWorker.perform_async
        SomeWorker.drain

        NextMessageWorker.drain

        expect(Helpers.getMMSarr).to be_empty
        expect(Helpers.getSMSarr[1..-1]).to be_empty



        Timecop.travel(2015, 6, 30, 17, 30, 0) #on the 2nd Tues!
      
        SomeWorker.perform_async
        SomeWorker.drain

        NextMessageWorker.drain

        expect(Helpers.getMMSarr).to be_empty
        expect(Helpers.getSMSarr[1..-1]).to be_empty


        Timecop.travel(2015, 7, 2, 17, 30, 0) #on the 2nd Thurs!
      
        SomeWorker.perform_async
        SomeWorker.drain

        NextMessageWorker.drain

        expect(Helpers.getMMSarr).to be_empty
        expect(Helpers.getSMSarr[1..-1]).to be_empty





        Timecop.travel(2015, 7, 7, 17, 30, 0) #on the third Tuesday!

        SomeWorker.perform_async
        SomeWorker.drain

        NextMessageWorker.drain

        NewTextWorker.drain

        expect(Helpers.getMMSarr).to_not be_empty
        expect(Helpers.getSMSarr[1..-1]).to_not be_empty
        expect(Helpers.getSMSarr.last).to include(Text::END_BREAK)

        puts "here it is 1: " + Helpers.getSMSarr.last


        Timecop.travel(2015, 7, 9, 17, 30, 0) #on third Thurs!

        SomeWorker.perform_async
        SomeWorker.drain

        NextMessageWorker.drain
        NewTextWorker.drain


        puts "here it is 2: " + Helpers.getSMSarr.last


        expect(Helpers.getMMSarr).to_not be_empty
        expect(Helpers.getSMSarr[1..-1]).to_not be_empty
        expect(Helpers.getSMSarr.last).to_not include(Text::END_BREAK)


        puts Helpers.getSMSarr

      end



        it "will include the StoryTime \'back after break \' message the first time, not the second" do
        @user.reload
        expect(@user.subscribed).to eq true
        get '/test/+15612125833/'+Text::BREAK+"/ATT"

        Timecop.travel(2015, 7, 7, 17, 30, 0) #on next Tuesday!

        SomeWorker.perform_async
        SomeWorker.drain

        NextMessageWorker.drain

        # to include Text::BREAK_END

        # expect(Helpers.getMMSarr).to_not be_empty
        # expect(Helpers.getSMSarr).to_not be_empty

        Timecop.travel(2015, 7, 9, 17, 30, 0) #on next Thurs!

        SomeWorker.perform_async
        SomeWorker.drain

        NextMessageWorker.drain

        # to not include Text::BREAK_END

        # expect(Helpers.getMMSarr).to_not be_empty
        # expect(Helpers.getSMSarr).to_not be_empty

      end


      it "sends the StoryTime \'start break \' message" do
        @user.reload
        expect(@user.subscribed).to eq true
        get '/test/+15612125833/'+Text::BREAK+"/ATT"

        # to include Text::BREAK_END

        expect(Helpers.getMMSarr).to be_empty
        expect(Helpers.getSMSarr).to eq [Text::START_BREAK]

      end

      it "properly updates ON_BREAK and DAYS_LEFT_ON_BREAK after break cmd" do
        @user.reload
        expect(@user.subscribed).to eq true

        expect(@user.on_break).to eq false
        expect(@user.days_left_on_break).to eq nil
        get '/test/+15612125833/'+Text::BREAK+"/ATT"

        @user.reload

        expect(@user.on_break).to eq true
        expect(@user.days_left_on_break).to eq Text::BREAK_LENGTH
        expect(@user.days_left_on_break).to eq 4

      end


    end



    describe 'Autosignup' do


      it "properly saves locale info" do
        @user = User.find_by_phone("+15612125831")
        expect(@user).to be nil 
        
        Signup.enroll(["+15612125831"], 'en', {Carrier: "ATT"})
        @user = User.find_by_phone("+15612125831")
        @user.reload
        expect(@user).to_not be nil

        expect(@user.locale).to eq 'en'
      end

       it "works for es" do
        @user = User.find_by_phone("+15612125831")
        expect(@user).to be nil 
        
        Signup.enroll(["+15612125831"], 'es', {Carrier: "ATT"})
        @user = User.find_by_phone("+15612125831")
        @user.reload
        expect(@user).to_not be nil

        expect(@user.locale).to eq 'es'
        expect(Helpers.getSMSarr[0]).to_not eq Text::START_SMS_1 + "2" +Text::START_SMS_2
        puts Helpers.getSMSarr[0]
      end

      it "has getWait giving values every 2 seconds." do 
        Signup.initialize_user_count()
       
        (0..40).each do |num|
         expect(wait = Signup.getWait).to eq(num*2)
         
         if num == 0 || num == 40
          puts wait
         elsif num == 1
          puts '...'
         end


        end

      end



      it "properly sends the no_signup_match message" do
        get '/test/555/sample%20STORY%20request/ATT' #improper sample request
       
        i18n = R18n::I18n.new('en', ::R18n.default_places)
        R18n.thread_set(i18n)

        R18n.set 'en'
        expect(R18n.t.error.no_signup_match).to_not eq nil
        expect(Helpers.getSMSarr[0]).to eq R18n.t.error.no_signup_match
        puts  Helpers.getSMSarr[0]
      end

      it "enrolls with time 21:30 UTC (17:30 EST)" do
        Signup.enroll(["+15612125831"], 'en', {Carrier: "ATT"})
        @user = User.find_by_phone("+15612125831")

        expect(@user.time.zone).to eq "UTC"
        expect(@user.time.hour).to eq 21
        expect(@user.time.min).to eq 30
        puts @user.time
      end

      it "sends a sprint-chopped long message for ES on signup" do

        i18n = R18n::I18n.new('es', ::R18n.default_places) #this chunk seems to create a new R18n thread
        R18n.thread_set(i18n)

        R18n.set 'es'

        Sidekiq::Testing.inline! do
          Signup.enroll(["+15612125832"], 'es', {Carrier: Text::SPRINT})
        end
        @user = User.find_by_phone("+15612125832")



        expect(Helpers.getSMSarr.length).to eq 2
        expect(Helpers.getMMSarr.first).to eq R18n.t.first_mms

        puts Helpers.getSMSarr
      end

      it "doesn't chop long message for non-sprint ES on signup" do
        i18n = R18n::I18n.new('es', ::R18n.default_places)
        R18n.thread_set(i18n)
        R18n.set 'es'

        Sidekiq::Testing.inline! do
          Signup.enroll(["+15612125831"], 'es', {Carrier: "ATT"})
        end
        @user = User.find_by_phone("+15612125831")
      

        expect(Helpers.getSMSarr.length).to eq 1
        expect(Helpers.getMMSarr.first).to eq R18n.t.first_mms

        puts Helpers.getSMSarr
      end

      it "has different spanish/english responses" do 
        i18n = R18n::I18n.new('es', ::R18n.default_places)
        R18n.thread_set(i18n)
        R18n.set 'es'


        span_arr = [] #array of spanish commands

        #load array with commands
        span_arr.push R18n.t.commands.help.to_s
        span_arr.push R18n.t.commands.stop.to_s
        span_arr.push R18n.t.commands.text.to_s
        span_arr.push R18n.t.commands.story.to_s
        span_arr.push R18n.t.commands.sample.to_s
        span_arr.push R18n.t.commands.example.to_s
        span_arr.push R18n.t.commands.break.to_s

        span_arr.push R18n.t.start.normal.to_s
        span_arr.push R18n.t.start.sprint.to_s

        span_arr.push R18n.t.mms_update.to_s

        span_arr.push R18n.t.help.normal.to_s
        span_arr.push R18n.t.help.sprint.to_s

        span_arr.push R18n.t.error.no_option.to_s
        span_arr.push R18n.t.error.bad_choice.to_s

        span_arr.push R18n.t.first_mms.to_s

        i18n = R18n::I18n.new('en', ::R18n.default_places)
        R18n.thread_set(i18n)
        R18n.set 'en'
        engl_arr = [] #array of english commands

        #load array with commands
        engl_arr.push R18n.t.commands.help.to_s
        engl_arr.push R18n.t.commands.stop.to_s
        engl_arr.push R18n.t.commands.text.to_s
        engl_arr.push R18n.t.commands.story.to_s
        engl_arr.push R18n.t.commands.sample.to_s
        engl_arr.push R18n.t.commands.example.to_s
        engl_arr.push R18n.t.commands.break.to_s

        engl_arr.push R18n.t.start.normal.to_s
        engl_arr.push R18n.t.start.sprint.to_s

        engl_arr.push R18n.t.mms_update.to_s

        engl_arr.push R18n.t.help.normal.to_s
        engl_arr.push R18n.t.help.sprint.to_s

        engl_arr.push R18n.t.error.no_option.to_s
        engl_arr.push R18n.t.error.bad_choice.to_s

        engl_arr.push R18n.t.first_mms.to_s

        engl_arr.each_with_index do |engl, i|
          expect(engl).to_not eq span_arr[i] #the commands shouldn't be the same
          puts "#{engl} != #{span_arr[i]}"
        end  
      end









    end








# STAGE 2 TESTS 
#   it "registers numeric age" do
#   	get '/test/111/STORY'
#   	get '/test/111/091412'
#   	expect(Helpers.getSimpleSMS).to eq("StoryTime: Great! You've got free nightly stories. Reply with your preferred time to receive stories (e.g. 6:30pm)")
#   end

#   it "registers age in words" do
#   	get '/test/222/STORY'
#   	get '/test/222/011811'
#   	expect(Helpers.getSimpleSMS).to eq("StoryTime: Great! You've got free nightly stories. Reply with your preferred time to receive stories (e.g. 6:30pm)")
#   end

#   it "rejects non-age" do
#   	get '/test/1000/STORY'
#   	get '/test/1000/badphone'
#   	expect(Helpers.getSimpleSMS).to eq("We did not understand what you typed. Please reply with your child's birthdate in MMDDYY format. For questions about StoryTime, reply HELP. To Stop messages, reply STOP.")
#   end

# # STAGE 3 TESTS
# 	it "registers timepm" do
# 		get '/test/833/STORY'
# 		get '/test/833/091412'
# 		get "/test/833/6:00pm"
# 		expect(Helpers.getSimpleSMS).to eq("StoryTime: Sounds good! We'll send you and your child a new story each night at 6:00pm.")
# 	end


#   it "registers time then pm" do
#     get '/test/844/STORY'
#     get '/test/844/091412'
#     get '/test/844/6:00%20pm'
#     expect(Helpers.getSimpleSMS).to eq("StoryTime: Sounds good! We'll send you and your child a new story each night at 6:00pm.")
#   end


# 	it "rejects a bad time registration" do
# 		get '/test/633/STORY'
# 		get '/test/633/091412'
# 		get '/test/633/boo'
# 		expect(Helpers.getSimpleSMS).to eq("(1/2)We did not understand what you typed. Reply with your child's preferred time to receive stories (e.g. 6:30pm).")	
# 	end


# # PASSED ALL STAGES TESTS
# 	it "doesn't recognize further commands" do
# 		get '/test/488/STORY'
# 		get '/test/488/091412'
# 		get '/test/488/6:00pm'
# 		get '/test/488/hello'
# 		expect(Helpers.getSimpleSMS).to eq("This service is automatic. We did not understand what you typed. For questions about StoryTime, reply HELP. To Stop messages, reply STOP.")
# 	end

end


