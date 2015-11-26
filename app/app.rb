#  app.rb 	                                  Phil Esterman		
# 
#  Main control structure for receiving, responding to SMS. 
#  --------------------------------------------------------

#########  DEPENDENCIES  #########

#config the load path 
require 'bundler/setup'

#siantra dependencies 
require 'sinatra'
require 'sinatra/activerecord' #sinatra w/ DB
require_relative '../config/environments' #DB configuration
require_relative '../models/user' #add User model

set :root, File.join(File.dirname(__FILE__), '../')


#scheduled background jobs 
require 'sidekiq'
require 'sidetiq'
require 'sidekiq/web'
require 'sidekiq/api' 

#twilio texting API
require 'twilio-ruby'

#internationalization
require 'sinatra/r18n'
#temp: constants not yet translated
require_relative '../constants'

#misc
require 'redis'
require_relative '../config/initializers/redis'

#sending mmessages 
require_relative '../message'
require_relative '../messageSeries'
require_relative '../workers/some_worker'
require_relative '../helpers.rb'

#timing
require 'time'
require_relative '../lib/set_time'

configure :production do
  require 'newrelic_rpm'
end

#enrollment
require_relative './enroll'

#set default locale to english
# R18n.default_places = '../i18n/'
R18n::I18n.default = 'en'

#set mode (production or test)
MODE = ENV['RACK_ENV']

PRO = "production"
TEST = "test"

#constants (untranslated)
include Text


#########  ROUTES  #########

#root
get '/' do
	erb :main
end

#twilio failed
get '/failed' do
	Helpers.smsRespondHelper("StoryTime: Hi! " + 
		"We're updating StoryTime now and are offline, " +
		     "but check back in the next day!")
end

#voice call
get '/called' do
  Twilio::TwiML::Response.new do |r|
    r.Play "http://www.joinstorytime.com/mp3"
  end.text
end

# register an incoming SMS
get '/sms' do
	app_start(params)
end

# mock entrypoint for testing
get '/test/:From/:Body/:Carrier' do
	app_start(params)
end



#########  WORKFLOW  ######### 

# Set locale, then enter response workflow.
#	@param params => fake user data:
# 	  [Carrier: "ATT", Body: "BREAK"] etc. 
#   	-(For TEST mode. Normally given by Twilio.)	
def app_start(params) 
	#1. Set locale.	
	@user = User.find_by_phone params[:From]
	
	if @user
		locale = @user.locale
	elsif params[:locale]
		locale = params[:locale]
	else
		locale = "en"
	end
	#2. Workflow. 
	app_workflow(params, locale)
end


#manages entire registration workflow, keyword-selecting
#defaults to English.
def app_workflow(params, locale)

	#strip whitespace (trailing and leading)
	params[:Body] = params[:Body].strip
	params[:Body].gsub!(/[\.\,\!]/, '') #rid of periods, commas, exclamation points

	@user = User.find_by_phone(params[:From]) #check if already registered.

	#PRO, set locale for returning user, w/in thread 
	if locale != nil && @user != nil
		i18n = R18n::I18n.new(@user.locale, ::R18n.default_places)
        R18n.thread_set(i18n)
	end

	#first reply: new user texts in STORY
	if params[:Body].casecmp(R18n.t.commands.story) == 0 && 
			(@user == nil || @user.sample == true)
		app_enroll(params, params[:From], locale, STORY)

	elsif params[:Body].casecmp(R18n.t.commands.sample) == 0 ||
			params[:Body].casecmp(R18n.t.commands.example) == 0
		app_enroll(params, params[:From], locale, SAMPLE)

	elsif @user == nil
		Helpers.text(R18n.t.error.no_signup_match, 
			R18n.t.error.no_signup_match, params[:From])
	elsif @user.sample == true
		Helpers.text(R18n.t.sample.post, R18n.t.sample.post,
											    @user.phone)
	#if auto-dropped (or if choose to drop mid-series), returning
	elsif (@user.next_index_in_series == 999 || 
				 @user.awaiting_choice == true) &&
		  (@user.subscribed == false && 
		  		 params[:Body].casecmp(R18n.t.commands.story) == 0)

		#REACTIVATE SUBSCRIPTION
			@user.update(subscribed: true)
			msg = R18n.t.stop.resubscribe.short + 
				"\n\n" + R18n.t.choice.no_greet[@user.series_number]
					 #longer message, give more newlines

			@user.update(next_index_in_series: 0)
			@user.update(awaiting_choice: true)

			Helpers.text(msg, msg, @user.phone)
	#if returning after manually stopping (not in mid - series)
	elsif @user.subscribed == false && 
			params[:Body].casecmp(R18n.t.commands.story) == 0 
		#REACTIVATE SUBSCRIPTION
		@user.update(subscribed: true)
		Helpers.text(R18n.t.stop.resubscribe.long, 
			R18n.t.stop.resubscribe.long, @user.phone)

	elsif params[:Body].casecmp(R18n.t.commands.help) == 0 #Text::HELP option
	  	#default 2 days a week
	  	if @user.days_per_week == nil
	  		@user.update(days_per_week: 2)
	  	end

	  	#find the day names
	  	case @user.days_per_week
	  	when 1
	  			dayNames = R18n.t.weekday.wed

	  	when 2, nil
	  		if @user.carrier == SPRINT
	  			dayNames =  R18n.t.weekday.sprint.tue +
	  			 "/" + R18n.t.weekday.sprint.th
	  		else           
	  			dayNames = R18n.t.weekday.normal.tue +
	  			 "/" + R18n.t.weekday.normal.th
	  		end
	  	when 3
	  		if @user.carrier == SPRINT
	  			dayNames = R18n.t.weekday.letters.M + 
	  				 "-" + R18n.t.weekday.letters.W + 
	  				 "-" + R18n.t.weekday.letters.F
	  		else           
	  			dayNames = R18n.t.weekday.mon + 
	  			     "/" + R18n.t.weekday.wed +
	  			     "/" + R18n.t.weekday.fri
	  		end
	  	else
	  		puts "ERR: invalid days of week"
	  	end

	  	Helpers.text(R18n.t.help.normal(dayNames).to_s,
	  		 R18n.t.help.sprint(dayNames).to_s, @user.phone)

	elsif params[:Body].casecmp(R18n.t.commands.break) == 0
		@user.update(on_break: true)
		@user.update(days_left_on_break: Text::BREAK_LENGTH)

		Helpers.text(R18n.t.break.start, R18n.t.break.start,
											    @user.phone)

	elsif params[:Body].casecmp("STOP NOW") == 0 ||
		  params[:Body].casecmp(R18n.t.commands.stop) == 0#STOP option

		if MODE == PRO
		#SAVE QUITTERS
			REDIS.set(@user.phone+":quit", "true") 
			#update if the user quits
			#EX: REDIS.zadd("+15612125831:quit", true)  
		end
		#change subscription
		@user.update(subscribed: false)
		note = params[:From].to_s + "quit StoryTime."
		Helpers.new_text(note, note, "+15612125831")


	elsif params[:Body].casecmp(R18n.t.commands.text) == 0 #TEXT option		
		#change mms to sms
		@user.update(mms: false)
		Helpers.text(R18n.t.mms_update, R18n.t.mms_update,
											  @user.phone)
	elsif params[:Body].casecmp("REDO") == 0 #texted STORY
		#no need to manually undo birthdate
		Helpers.text(Text::REDO_BIRTHDATE, Text::REDO_BIRTHDATE,
												    @user.phone)
	#Responds with a letter when prompted to choose a series
	#Account for quotations
	elsif @user.awaiting_choice == true &&
	   /\A[']{0,1}["]{0,1}[a-zA-Z][']{0,1}["]{0,1}\z/ =~ params[:Body]			

		body = params[:Body]
		#has quotations => extract the juicy part
		if  !(/\A[a-zA-Z]\z/ =~ params[:Body])
			body = params[:Body][1,1]
		end
		body.downcase!

		#push back to zero incase 
		#changed to 999 to denote one 'day' after
        @user.update(next_index_in_series: 0)

		#check if valid choice
		if MessageSeries.codeIsInHash(body + @user.series_number.to_s)
	 			
			#update the series choice
			@user.update(series_choice: body)
			@user.update(awaiting_choice: false)

		    messageSeriesHash = MessageSeries.
		    						getMessageSeriesHash
		    story = messageSeriesHash[@user.series_choice +
		    						  @user.series_number.to_s][0]
			if @user.mms == true
				#incase of just one photo, this also updates user-info.
				#sends last photo in advance
				NextMessageWorker.perform_in(17.seconds, story.getSMS,
								  story.getMmsArr[1..-1], @user.phone)
				 #don't need to send stack 
				 #if a one-pager.
				if story.getMmsArr.length > 1
					 #replies with first photo immediately
					Helpers.mms(story.getMmsArr[0], @user.phone)
				else
					#if just one photo, replies
					#w/ photo and sms
					Helpers.text_and_mms(story.getSMS,
					  story.getMmsArr[0], @user.phone)
			    end

			else # just SMS
		        NextMessageWorker.updateUser(@user.phone,
		        					    story.getPoemSMS)
		        Helpers.text(story.getPoemSMS, story.getPoemSMS,
		        								    @user.phone)      
			end
	 	else	 			
			Helpers.text(R18n.t.error.bad_choice, 
				R18n.t.error.bad_choice, @user.phone)
	 	end				

	#response matches nothing
	else
		Helpers.text(R18n.t.error.no_option.to_s, 
			R18n.t.error.no_option.to_str, @user.phone)

	end#signup flow

end



#begin sidetiq recurrence bkg tasks
get '/worker' do
	SomeWorker.perform_async 
	redirect to('/')
end

get '/mp3' do
	send_file File.join(settings.public_folder, 
							'storytime_message.mp3')
end








