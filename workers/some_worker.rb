# require '.config/environments'
require 'rubygems'
require 'twilio-ruby'
require 'sinatra/activerecord'
require_relative '../models/user'           #add the user model
require 'sidekiq'
require 'sidetiq'

require_relative '../sprint'
require_relative '../message'
require_relative '../messageSeries'

class SomeWorker
  include Sidekiq::Worker
  include Sidetiq::Schedulable
  
  sidekiq_options :queue => :default


  MAX_TEXT = 155 #leaves room for (1/6) at start (160 char msg)
  
  TIME_SMS_NORMAL = "StoryTime: Hey there! We want to make StoryTime better for you. When do you want to receive stories (e.g. 5:00pm)?

  Rememeber screentime within 2hrs before bedtime can delay children's sleep and carry health risks, so please read earlier."

  TIME_SMS_SPRINT_1 = "(1/2) StoryTime: Hi! We want to make StoryTime better for you. When do you want to receive stories (e.g. 5:00pm)?"

  TIME_SMS_SPRINT_2 = "(2/2) Rememeber screentime within 2hrs before bedtime can delay children's sleep and carry health risks, so please read earlier."

  BIRTHDATE_UPDATE = "StoryTime: If you want the best stories for your child's age, reply with your child's birthdate in MMYY format (e.g. 0912 for September 2012)."


DAY_LATE = "StoryTime: Hi! We noticed you didn't choose your last story. To continue getting StoryTime stories, just reply \"yes\"\n\nThanks :)"


  DROPPED = "We haven't heard from you, so we'll stop sending you messages. To get StoryTime again, reply with STORY"

SERIES_CHOICES = ["StoryTime: Hi! You can now choose new stories. Do you want stories about Marley the puppy or about Bruce the moose?\n\nReply \"p\" for puppy or \"m\" for moose."]




  if ENV['MY_MACHINE?'] != "true" #on the INTERNET

    UPDATE_TIME = "20:00" #time for the birthdate and time updates
  
  else #my machine
 
    UPDATE_TIME = "16:00"
 
  end

	sidekiq_options retry: false #if fails, don't resent (multiple texts)


  recurrence { hourly.minute_of_hour(0, 2, 4, 6, 8, 10,
  									12, 14, 16, 18, 20, 22, 24, 26, 28, 30,
  									32, 34, 36, 38, 40, 42, 44, 46, 48, 50,
  									52, 54, 56, 58) } #set explicitly because of ice-cube sluggishness



  def self.buildStoryArr

    @@messageArr = Message.getMessageArray

    @@messageSeriesHash = MessageSeries.getMessageSeriesHash

  end


  def perform(*args)

    account_sid = ENV['TW_ACCOUNT_SID']
    auth_token = ENV['TW_AUTH_TOKEN']

    @client = Twilio::REST::Client.new account_sid, auth_token


    puts "SystemTime is: " + SomeWorker.cleanSysTime

    # send Twilio message
    # ignores improperly registered users, AND users who have unsubscribed
    User.where(subscribed: true).find_each do |user|

      #logging info
      print 'Send story to time ' + SomeWorker.convertTimeTo24(user.time) + "?: "
      if SomeWorker.sendStory?(user)
        puts 'YES!!'
      else
         puts 'No.'
      end


      if user.set_time == false && SomeWorker.cleanSysTime == UPDATE_TIME && user.story_number == 2 #Customize time 
          
        if user.carrier == SPRINT
                    message = @client.account.messages.create(
                      :body => TIME_SMS_SPRINT_1,
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679")   # Replace with your Twilio number

                puts "Sent time update message part 1 to " + user.phone + "\n\n"

                sleep 10

                     message = @client.account.messages.create(
                      :body => TIME_SMS_SPRINT_2,
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679")   # Replace with your Twilio number

                puts "Sent time update message part 2 to " + user.phone + "\n\n"

                sleep 1

        else #NORMAL carrier

                    message = @client.account.messages.create(
                      :body => TIME_SMS_NORMAL,
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679")   # Replace with your Twilio number

                puts "Sent time update message part 1 to " + user.phone + "\n\n"

                sleep 1
        end

        #They've set their own time, so don't ask again
        user.update(set_time: true)

      end


      #UPDATE Birthdate! 
      if user.set_birthdate == false && SomeWorker.cleanSysTime == UPDATE_TIME && user.story_number == 4 #Customize time 


                    message = @client.account.messages.create(
                      :body => BIRTHDATE_UPDATE,
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679")   # Replace with your Twilio number

                puts "Sent birthday update message part 1 to " + user.phone + "\n\n"

                sleep 1

          user.update(set_birthdate: true)

      end





        if SomeWorker.sendStory?(user) 


         #Should the user be asked to choose a series?
          #If it's all of these:
          #0) not awaiting chioce
          #a) their time, 
          #b) their third story, or every third one thereafter.
          #c) they're not in the middle of a series
          if user.awaiting_choice == false && (SomeWorker.sendStory?(user) &&  (user.story_number == 1 || (user.story_number != 0 && user.story_number % 3 == 0)) && next_index_in_series == nil)

            #get set for first in series
            user.update(next_index_in_series: 0)
            user.update(awaiting_choice: true)

            #choose a series
                message = @client.account.messages.create(
                  :to => myphone,     # Replace with your phone number
                  :from => "+17377778679",
                  :body => SERIES_CHOICES[user.series_number])

          elsif user.awaiting_choice == true && user.next_index_in_series == 0 # the first time they haven't responded
          
             message = @client.account.messages.create(
                      :to => myphone,     # Replace with your phone number
                      :from => "+17377778679",
                      :body => DAY_LATE
                      )

             user.update(next_index_in_series: 999)  

          elsif user.next_index_in_series == 999 #the second time they haven't responded


             user.update(subscribed: false)

             message = @client.account.messages.create(
                      :to => myphone,     # Replace with your phone number
                      :from => "+17377778679",
                      :body => DROPPED
                      )



          #send STORY or SERIES, but not if awaiting series response
          elsif (user.series_choice == nil && user.next_index_in_series == nil) || user.series_choice != nil

            #SERIES
            if user.series_choice != nil

              story = @@messageSeriesHash[user.series_choice + user.series_number][user.next_index_in_series]

            #STORY
            else 

              story = @@messageArr[user.story_number] 
            end 
            

            ##appended feedback request after first week, then every two weeks! 
            if (user.story_number - user.last_feedback == 2) && (user.story_number > 2)
                warning = "\n\nIf we don't hear from you, you will stop receiving StoryTime msgs."
            else
              warning = "" #NOTHING
            end


            #JUST SMS MESSAGING!
            if user.mms == false

              if user.carrier == "Sprint Spectrum, L.P." 

                sprintArr = Sprint.chop(story.getPoemSMS + warning)

                sprintArr.each_with_index do |text, index|  
                  message = @client.account.messages.create(
                    :body => text,
                    :to => user.phone,     # Replace with your phone number
                    :from => "+17377778679")   # Replace with your Twilio number

                  puts "Sent message part #{index} to" + user.phone + "\n\n"

                  sleep 2
                end

              else # NOT SPRINT (normal carrier) 

                message = @client.account.messages.create(
                    :body => story.getPoemSMS + warning,
                    :to => user.phone,     # Replace with your phone number
                    :from => "+17377778679")   # Replace with your Twilio number

                puts "Sent message to" + user.phone + "\n\n"

              end# end of sprint/non-sprint sub block


            else #MULTIMEDIA MESSAGING (MMS)!

              #arr for sprint
              sprintArr = Sprint.chop(story.getSMS + warning)

              # if NOT sprint or if under 160 char
              if user.carrier != "Sprint Spectrum, L.P." ||
                 (sprintArr.length == 1)

              # if there's a single picture message
                if story.getMmsArr.length == 1

                  message = @client.account.messages.create(
                    :body => story.getSMS + warning,
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679",
                      :media_url => story.getMmsArr[0])   # Replace with your Twilio number

                puts "Sent message to" + user.phone + "\n\n"

                elsif story.mmsArr.length == 2
                  #first picture (no SMS)
                  message = @client.account.messages.create(
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679",
                      :media_url => story.getMmsArr[0])   # Replace with your Twilio number

                  puts "Sent first photo to " + user.phone + "\n\n"

                  sleep 20
                  #second picture with SMS
                  message = @client.account.messages.create(
                    :body => story.getSMS + warning,
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679",
                      :media_url => story.getMmsArr[1])   # Replace with your Twilio number

                puts "Sent seecond photo with message to" + user.phone + "\n\n"

             #THREE MMS
                elsif story.mmsArr.length == 3
                  #first picture (no SMS)
                  message = @client.account.messages.create(
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679",
                      :media_url => story.getMmsArr[0])   # Replace with your Twilio number

                  puts "Sent first photo to " + user.phone + "\n\n"

                  sleep 20
                  #second picture (no SMS)
                  message = @client.account.messages.create(
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679",
                      :media_url => story.getMmsArr[1])   # Replace with your Twilio number

                puts "Sent seecond photo with message to" + user.phone + "\n\n"

                  sleep 20
                  #THIRD picture with SMS
                  message = @client.account.messages.create(
                    :body => story.getSMS + warning,
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679",
                      :media_url => story.getMMSArr[2])   # Replace with your Twilio number



                else 
                  puts "AN IMPOSSIBLE NUMBER OF PICTURE MESSAGES"
               
                end

                sleep 2 #sleep after sending msg

              else #a SPRINT phone with message greater than 160 char!

                #ONE PICTURE
                if story.mmsArr.length == 1

                  #send single picture
                  message = @client.account.messages.create(
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679",
                      :media_url => story.getMMSArr[0])   # Replace with your Twilio number

                  # sleep 5 JUNE 30
                  sleep 20


                  sprintArr.each_with_index do |text, index|  
                    message = @client.account.messages.create(
                      :body => text,
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679")   # Replace with your Twilio number

                    puts "Sent message part #{index} to" + user.phone + "\n\n"

                    # sleep 2 JUNE 30
                     sleep 5

                  end

                elsif story.mmsArr.length == 2            

                  #send first picture
                  message = @client.account.messages.create(
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679",
                      :media_url => story.getMMSArr[0])   # Replace with your Twilio number

                  puts "Sent first photo!"
                  sleep 20
                  
                  #send second picture
                  message = @client.account.messages.create(
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679",
                      :media_url => story.getMMSArr[1])   # Replace with your Twilio number

                  puts "Sent second photo!"
                  sleep 20

                  #send sms chain
                  sprintArr.each_with_index do |text, index|  
                    message = @client.account.messages.create(
                      :body => text,
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679")   # Replace with your Twilio number

                    puts "Sent message part #{index} to" + user.phone + "\n\n"
                    sleep 1

                  end


                           #THREE MMS
                elsif story.mmsArr.length == 3
                  #first picture (no SMS)
                  message = @client.account.messages.create(
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679",
                      :media_url => story.getMMSArr[0])   # Replace with your Twilio number

                  puts "Sent first photo to " + user.phone + "\n\n"

                  sleep 20
                  #second picture (no SMS)
                  message = @client.account.messages.create(
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679",
                      :media_url => story.getMMSArr[1])   # Replace with your Twilio number

                puts "Sent seecond photo with message to" + user.phone + "\n\n"

                  sleep 20
                  #THIRD picture with SMS
                  message = @client.account.messages.create(
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679",
                      :media_url => story.getMMSArr[2])   # Replace with your Twilio number 

                  sleep 20


                  #send sms chain
                  sprintArr.each_with_index do |text, index|  
                    message = @client.account.messages.create(
                      :body => text,
                      :to => user.phone,     # Replace with your phone number
                      :from => "+17377778679")   # Replace with your Twilio number

                    puts "Sent message part #{index} to" + user.phone + "\n\n"
                    sleep 1
                  end

                else

                  puts "AN IMPOSSIBLE NUMBER OF PICTURES!"

                end#end sub-sprint

              end#end nonsprint/sprint

            end#MMS or SMS

              #updating story or series number
              #next_index_in_series == nil (or series_choice == nil?) means that you're not in a series
              if user.next_index_in_series != nil
                user.update(next_index_in_series: (user.next_index_in_series + 1))

                #exit series if time's up
                if user.next_index_in_series == @@messageSeriesArr[user.series_number].length

                  ##return variable to nil: (nil, which means "you're asking the wrong question-- I'm not in a series")
                  user.update(next_index_in_series: nil)
                  user.update(series_choice: nil)

                  #get ready for next series
                  user.udpate(series_number: user.series_number + 1)

                end

              else
                user.update(story_number: user.story_number + 1)
              end

          end#end story_subpart

        end#end sendStory? large

    end#end User.do

        
    puts "doing hard work!!" + "\n\n" 

  end #end perform method



  # converts one long 160+ character string into an array of <160 char strings
  def self.sprint(story) 

    sms = Array.new #array of texts to send seperately

    storyLen = story.length #characters in story

    totalChar = 0 #none counted so far

    startIndex = 0 

    smsNum = 1 #which sms you're on (starts with first)

    while (totalChar < storyLen - 1) #haven't divided up entire message yet

      if (totalChar + MAX_TEXT < storyLen) #if not on last message
        endIndex = startIndex + MAX_TEXT  
      else #if on last message
        endIndex = storyLen - 1 #endIndex is last index of story
      end

        while (story[endIndex-1] != "\n" || endIndex-1 == startIndex) && endIndex != storyLen-1 do  #find the latest newline before endIndex
          endIndex -= 1
        end

        if endIndex == startIndex #no newlines in block


          endIndex = startIndex + MAX_TEXT #recharge endindex
          
          while story[endIndex-1] != " "
          endIndex -= 1
          end

        end

      smsLen = endIndex - startIndex #chars in sms

      totalChar += smsLen #chars dealt with so far

      sms.push "(#{smsNum}/X)"+story[startIndex, smsLen]

      startIndex = endIndex

      smsNum += 1 #on the next message

    end

    sms.each do |text|
      text.gsub!(/[\/][X][)]/, "\/#{smsNum-1})")
    end

    return sms

  end



  #makes a hash to use in struct
  def self.makeHash(three, four, five)
    hash = { 3 => three, 4 => four, 5 => five}
    return hash
  end

  # helper methods

  # check if user's story time is in the next two minutes
  def self.sendStory?(user) #don't know object as parameter

    weekday = Time.new.wday 

    one_day_age = Time.now - 1.day

    
    if (((user.days_per_week == 3 && (weekday == 1 || weekday == 3 || weekday == 5)) || (user.days_per_week == 1 && (weekday == 3)) || ((user.days_per_week == 2 || user.days_per_week == nil) && (weekday == 2 || weekday == 4))) && (user.created_at <= one_day_age)) ||
      (user.phone == "+15612125831" || user.phone == "+15619008225") #SEND TO US EVERYDAY
                                                                     #SEND IF TUES OR THURS and NOT created this past day!
                                                                    #Note: this messes up if they created this past 5:00pm on a M or W
      currTime = SomeWorker.cleanSysTime
      userTime = SomeWorker.convertTimeTo24(user.time)

      currHour = currTime[0,2]   
      userHour = userTime[0,2]

      #CONVERTING FROM EASTERN TO UTC when not my machine!!!!
      if ENV['MY_MACHINE?'] != "true"
      userHour = ((userTime[0,2].to_i + 4) % 24).to_s
      end


      len = currTime.length 
      # assert(currTime.length == userTime.length, "lengths differ")
      # assert(len == 5, "lengths differ")

        currMin = currTime[3, len]
        userMin = userTime[3, len]

        currMin = currMin.to_i
        userMin = userMin.to_i    

      if currHour.to_i == userHour.to_i #same hour (03 converts to 3)

        if (userMin - currMin) < 2 && (userMin - currMin) >= 0 #send the message
          return true
        else
          return false
        end
      elsif (userHour.to_i == 1 + currHour.to_i) &&  
            ((currMin == 58 && userMin == 0) || (currMin == 59 && userMin == 1)) #the 5:58 send the 6:00 message
          return true
      else
        return false
      end

    else

      return false
    
    end#end weekday/first time

  end#end sendStory?

  # returns a cleaned version of the current system time in 24 hour version
  def self.cleanSysTime

    currTime = Time.new

    hours = currTime.hour
    min = currTime.min

    # check if min is single digit
    if min < 10
      min = min.to_s
      min = "0"+min #add zero infront 
    end

    # check if hour is single digit
    if hours < 10
    	hours = hours.to_s
    	hours = "0" + hours #add zero to front
    end

    	cleanedTime = hours.to_s+":"+min.to_s 


    return cleanedTime
  end

  # converts pm/am time into 24hour time 
  def self.convertTimeTo24(oldTime)


    len = oldTime.length
    hoursEndIndex = oldTime.index(':')
    
    hours = oldTime[0,hoursEndIndex]

    colonAndMinutes = oldTime[hoursEndIndex, 3] # [startIndex, length of substring]
      cleanedTime= hours + colonAndMinutes



    if oldTime[len-2,2] == "pm" && hours != "12" #if pm, add 12 to hours (unless noon)     

      hours = (hours.to_i + 12).to_s 
      cleanedTime = hours + colonAndMinutes

    elsif oldTime[len-2,2] == "pm" && hours == "12"

      cleanedTime = oldTime[0,len-2]

    else  #am version   

      cleanedTime = oldTime[0,len-2]

      if hours.to_i < 10 #add zero if single digit hour
        cleanedTime = "0" + cleanedTime
      end

      if hours == "12"   # 12:XXam convert to 00:XXam
        cleanedTime = "00" + colonAndMinutes
      end     

    end

    return cleanedTime

  end


#start doing stuff!
SomeWorker.buildStoryArr #Go!



end






  


  

