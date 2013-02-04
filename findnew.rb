#!/usr/bin/ruby

# Some users may have to change the path to Ruby above?

require 'open-uri'
require "rexml/document"
include REXML
# These are, I believe, included as part of standard Ruby install?


# Some logging if you run the script directly on command line for debugging
$logging=true

require 'config.rb'


if collectionSync!=""
  # We are just getting items from a single collection:
  baseuri="https://api.zotero.org/users/#{userid}/collections/#{collectionSync}/items"
else
  # We are grabbing all items
  baseuri="https://api.zotero.org/users/#{userid}/items"
end

itemuri="https://api.zotero.org/users/#{userid}/items"
keyuri="?key=#{key}&format=keys&order=dateModified"

# METHODS ----------------------------------------

def writeFile(writeData,wFile)
  File.open(wFile,'w') {|f| f.write(writeData)}
end

def appendFile(writeData,wFile)
  File.open(wFile,'a') {|f| f.write(writeData)}
end

def readFile(rFile)
  dataRead=File.open(rFile,'r') {|f| f.read}
  return dataRead
end

def log(logMessage)
  if logMessage
    if $logging 
      puts "LOG: "+logMessage
    end
  end
end

def checkError(errorMessage)
  # Add explanation for some errors
  if errorMessage=="403 Forbidden"
    log("The forbidden message often appears because your user id or key are invalid.")
  elsif errorMessage=="500 Internal Server Error"
    log("This error can happen if your collection id is invalid.")
  end
end

# END METHODS ----------------------------------

writeFile("0/0",progressFile)
# set the progress file to nothing
# this file is used to pass on progress of the script to the applescript that will run this ruby script


# GET LIST OF ITEMS FROM SERVER AND LOCAL ------
  begin
    serverKeyList=open(baseuri+keyuri) {|f| f.read}
  rescue OpenURI::HTTPError => errorMsg
    seterror="ERROR: Error loading list of keys on server: #{errorMsg}"
    log(seterror)
    writeFile(seterror,progressFile)
    checkError(errorMsg.message)
    exit
  end

  if serverKeyList=="An error occurred"
    seterror="ERROR: Zotero returned an error. Did you enter the correct key, user id, and collection id?"
    log(seterror)
    writeFile(seterror,progressFile)
  end
  # Grabs a list of all the IDs for items in the Zotero database, by datemodified

  if File.exists?(local)
    localKeyList=readFile(local)
  else
    localKeyList=""
  end
  # Get the local list of IDs for Zotero items

  serverKeyArray=serverKeyList.split("\n")
  # put all the IDs obtained from the server into an array
  log("SERVER KEY LIST ITEM COUNT: "+serverKeyArray.count.to_s)
  localKeyArray=localKeyList.split("\n")
  # put all the IDs obtained from the local list of keys into an array
  log("LOCAL FILE ITEM COUNT: "+localKeyArray.count.to_s)

# FIND MISSING ITEMS ---------------------------

  missingItems=serverKeyArray-localKeyArray
  # determine what IDs are in the online Zotero database not in the local key list
  
  writeFile("0/#{missingItems.count}",progressFile)
  log("count of missing items: "+missingItems.count.to_s)

  # missingitems.each {|a| puts a}

  missingItemData=""
  mycount=0
  foundcount=0
  
  # now step through each of the items that were not in the local key list
  # and download the info for it
  missingItems.each {|item|
    mycount+=1
    log("#{mycount}/#{missingItems.count}")
    log("#{item}")
    writeFile("#{mycount}/#{missingItems.count}",progressFile)
    # record the progress made in downloading data to give feedback to applescript
    # now grab the data for each missing item:
    begin
      itemData=open(itemuri+"/"+item+"?key=#{key}&format=atom") {|f| f.read}
    rescue OpenURI::HTTPError => errorMsg
      seterror="Error loading data from item number #{mycount} on server: #{errorMsg}"
      log(seterror)
      writeFile(seterror,progressFile)
      checkError(errorMsg.message)
      exit
    end
    xmlData=Document.new itemData
  
    root=xmlData.root

    entries=root.elements.to_a("//entry")
    
    newType=entries[0].elements.to_a("zapi:itemType")[0].text 
    #get the item type for new item
    # this will return things like journalArticle, book, attachment, note
    if newType
      log(newType)
      foundcount+=1
      newTitle=entries[0].elements.to_a("title")[0].text
      log(newTitle)
      if entries[0].elements.to_a("zapi:creatorSummary")[0]
        newCreatorSummary=entries[0].elements.to_a("zapi:creatorSummary")[0].text
      else
        newCreatorSummary=""
      end
      log(newCreatorSummary)
      # this will return the last name of the author, if it is available
      newID=entries[0].elements.to_a("zapi:key")[0].text
      newUpdated=entries[0].elements.to_a("updated")[0].text
      
      newUp=""
      newAtType=""
      newURL=""
      if newType=="attachment" || newType=="note"
        # For attachments and notes, extract the Key of the item it is attached to
        newUp=entries[0].elements.to_a("link")[1].attributes["href"].gsub("https://api.zotero.org/users/#{userid}/items/",'')
        if newType=="attachment"
          # Find out what kind of attachment it is 
          begin
            newAtType=entries[0].elements["content"].elements["div"].elements["table"].elements["tr[@class='mimeType']"].elements["td"].text
          rescue NoMethodError
            # Some URLs have a URL attachment with no mimeType specified. I have only seen this with URLs so assume type of html/text
            newAtType="html/text"
          end
        end
      end

      # Grab the link for URL link attachments and webpages
      # Perhaps future version grabs link for all items? Journal articles etc. often link to online database
      if newAtType=="text/html" || newType=="webpage"
        newURL=entries[0].elements["content"].elements["div"].elements["table"].elements["tr[@class='url']"].elements["td"].text
      end
      
      # Put it all together in tab delimited form to put in the new file for the pass-off to the AppleScript
      # 1. TYPE 2. ID 3. TITLE  4. CREATOR SUMMARY  5. PARENT ID  6. ATTACHMENT TYPE  7. URL
      missingItemData=newType+"\t"+newID+"\t"+newTitle+"\t"+newCreatorSummary+"\t"+newUp+"\t"+newAtType+"\t"+newURL+"\n"
      
      newIDn=newID+"\n"
      if mycount==missingItems.count
        missingItemData.chomp!("\n")
        newIDn.chomp!
      end
      
      # When we have successfully downloaded data, save it to the new.txt and key.txt so we can restart here if something goes wrong
      # if ZotDevon.scpt finds a new.txt file that is not empty, it will prompt user to skip findnew.rb and first import downloaded
      # entries. That way, next import doesn't have to start from the beginning again. Otherwise, they can optionally choose to work from
      # backup key.txt file.
      appendFile(missingItemData,newDataFile)
      appendFile(newIDn,local)
    else
        puts "ERROR: No itemtype found for entry."
    end  
  }
  
  writeFile("Done/#{foundcount}",progressFile)
  # Register the time for this sync
  writeFile(Time.now.to_i,lastUpdateFile)


