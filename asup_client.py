import requests
import ConfigParser
import email
import time
import subprocess
from requests.auth import HTTPBasicAuth
import sys
import os
import shutil
from ast import literal_eval

class ASUP_Client():
    def __init__(self):
        config = ConfigParser.RawConfigParser()
        configFilePath = r'hedwig.cfg'
        config.read(configFilePath)
        self.appConf = config
        self.alertName = str(time.time())
        self.tempDir = self.appConf.get('hedwig', 'tmp.alerts.storage.path') + self.alertName + "/"
        self.required_files = set(literal_eval(self.appConf.get('hedwig', 'required.files')))

    def post_alerts(self):
        header = {'Accept': 'application/json', "Content-Type": "application/json"}
        alerts_url = self.appConf.get('hedwig', 'alerts.api.endpoint')
        #print 'Posting %s to %s' % (self.email_fields, alerts_url)
        respose =  requests.post(alerts_url, json=self.email_fields, auth=HTTPBasicAuth(self.appConf.get('hedwig', 'username'), self.appConf.get('hedwig', 'password')), headers=header)
        #jr = json.loads(respose.text())
        #print(respose.json())
        self.alert_id = respose.json()['id']
        print self.alert_id

    def get_alerts(self):
        alertsEndpoint = self.appConf.get('hedwig', 'alerts.api.endpoint')
        r = requests.get(alertsEndpoint, auth=HTTPBasicAuth(self.appConf.get('hedwig', 'username'), self.appConf.get('hedwig', 'password')))
        print(r.json())

    def unzip_attachment(self, attachmentPath):
        # TODO validate attachmentPath exists
        print("Will unzip: "+ attachmentPath)
        sevenz = self.appConf.get('hedwig', '7z')
        decompress = subprocess.check_output([sevenz, 'x', "-o" + self.tempDir, attachmentPath])
        print("Decompressed: "+attachmentPath+" to location: "+ self.tempDir+", output is: "+decompress)

    def parse_email(self, emailFile):
        # TODO validate email_file really exists
        print 'About to parse %s' % emailFile
        attachment_name = ""
        emailf = open(emailFile, 'rb')
        parsedEmail = email.message_from_file(emailf)
        if len(parsedEmail) == 0:
            print 'Failed to parse email at %s' % emailFile
            return
        if parsedEmail.is_multipart():
            for payload in parsedEmail.get_payload():
                ctype = payload.get_content_type()
                #print ctype
                if ctype in ['text/plain']:
                    #print 'Body >>>>>>>>>' + payload.get_payload()
                    self.email_fields = self.parse_email_body(str(payload.get_payload()))
                    print 'Finished parsing email body'
                elif ctype in ['application/octet-stream', 'application/x-7z-compressed']:
                    # This the attachment
                    attachment_name = "/tmp/" + self.alertName + payload.get_filename()
                    open(attachment_name, 'wb').write(payload.get_payload(decode=True))
                    print 'Finished writing attachment file at: %s' % attachment_name
                else :
                    print 'Unknown ctype: %s' % ctype
        else:
            print "Not a multi part email not sure how to process this"
        self.unzip_attachment(attachment_name)
        self.email_fields['alerts'] = str(self.parse_alert_data(self.tempDir))
        self.post_alerts()
        self.cleanup()

    def cleanup(self):
        shutil.rmtree(self.tempDir)
        print 'Cleaned up: '+self.tempDir


    def parse_email_body(self, email_body):
        email_body_data = {}
        if len(email_body) == 0:
            print 'Email body is empty, nothing to parse'
            return
        for token in email_body.split("\n"):
            field = ""
            field_value = ""
            if '=' in token:
                field = token.split("=")[0].strip('\n')
                field = field.lower()
                field_value = token.split("=")[1].strip('\n')
            else:
                print 'Unparsable property encountered in email body %s, skipping' % token
                continue
            email_body_data[field] = field_value
        return email_body_data

    def parse_alert_data(self, unzipped_files_dir):
        files_to_parse = []
        files_data = {}
        file_count = 0
        # change unzipped_files_dir to self.tempDir TODO
        for file in os.listdir(unzipped_files_dir):
            #print 'Adding file %s' % file
            if os.path.isfile(unzipped_files_dir+"/"+file):
                file_count = file_count + 1
                #if 'txt' not in str(file):
                if str(file) not in self.required_files:
                    print 'Skipping file: %s' % str(file)
                    continue
                # if file_count < 80:
                #     print 'Skipping file %s with count %d' % (str(file), file_count)
                #     continue
                # if file_count == 95:
                #     print 'Processed: %d files, stopping' % file_count
                #     break
                # if file_count < 95:
                #     print 'Skipping: %d files, continuing' % file_count
                #     continue
                files_to_parse.append(file)
                #if 'SYSCONFIG-A.txt' in str(file):
                fp = open(unzipped_files_dir + "/" + file, 'r')
                file_content = str(fp.read())
                file_content = file_content.replace("\r\n", "<br/>", -1)
                file_content = file_content.replace("\n", "<br/>", -1)
                #file_content = file_content.replace("\t", "", -1)
                file_content = file_content.replace("\t", "<tab/>", -1)
                #file_content = file_content.replace("\t", "&emsp;&emsp;&emsp;&emsp;", -1)
                files_data[file] = "<br/>" + file_content
                #files_data[file] = str(fp.read())
                #print files_data[file]
                fp.close()
                files_data[file] = files_data[file] + "<br/>"
               # files_data[file] = files_data[file] + "-------------------------------------------------------------------------<br/>"
        print 'Files to parsed: ' + str(files_to_parse)
        return files_data



alerts = ASUP_Client()
alerts.parse_email(sys.argv[1])
#alerts.test_required_files()

