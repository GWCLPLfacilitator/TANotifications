/*Created 12/22/2021 Gourav Bhardwaj
*
* Methods:
* fetchNotificationMetadata – Created to map the custom metadata types records with the help of email template label 
* sendNotification – This method is used to trigger email notification by taking input from flow
* sendNotificationToQueue - This method is used to trigger email or Bell notification to queue users as per their preference of notification type
* sendNotificationToUsers - This method is used to trigger email or Bell notification to users as per their preference of notification type
* sendBellNotification - This method is used to trigger Bell notification
* sendEmailNotification - This method is used to trigger email notification
*
*
* Update Log:
*   1/19/2022 Update to include ENUMS for meta data
*
* Test Class: TA_NotificationHandler_Test
*/

public without sharing class TA_NotificationHandler {

    public  enum NotificationContext {
        NETWORK_SNAPSHOT_COMPLETED,
        NETWORK_SNAPSHOT_SUBMITTED,
        PREQUAL_APPROVED,
        PREQUAL_REJECTED,
        PREQUAL_SUBMITTED,
        QUOTE_SUBMITTED,
        QUOTE_APPROVED,
        QUOTE_REJECTED,
        TRUCK_SERVICE_OPPORTUNITY_SUBMITTED,
        TRUCK_SERVICE_OPPORTUNITY_APPROVED,
        TRUCK_SERVICE_OPPORTUNITY_REJECTED,
        ESHOP_SUBMITTED_TEMPLATE,
        ESHOP_APPROVED,
        ESHOP_REJECTED,
        MOBILE_OPP_SUBMITTED,
        MOBILE_OPP_APPROVED,
        MOBILE_OPP_REJECTED,
        TA_ERA_APPROVED_TEMPLATE,
        TA_ERA_REJECTED_TEMPLATE,
        TA_ERA_SUBMISSION_TEMPLATE

    }

    public  enum OwnerType {
        USER,
        QUEUE
    }


    public static Map<String,TA_User_Notification_Type__mdt> contextNameToMetadata = new Map<String,TA_User_Notification_Type__mdt>();

    public static Map<String,TA_User_Notification_Type__mdt> fetchNotificationMetadata(){
        if(contextNameToMetadata.isEmpty()){
            for(TA_User_Notification_Type__mdt userNotification : [select TA_EmailFromAddress__c,TA_Email_Template__c,MasterLabel from TA_User_Notification_Type__mdt])
            {
                contextNameToMetadata.put(userNotification.MasterLabel,userNotification);
            }
        }
        system.debug('contextNameToMetadata : '+contextNameToMetadata);
        return contextNameToMetadata;
    }

    //This method is used to trigger email notification from flows
    @InvocableMethod (label ='Send Notification')
    public static void sendNotification (List<FlowInputs> request){
       system.debug('sendNotification request '+request.get(0).ownerType);
       
       if(request.get(0).ownerType==OwnerType.USER.name()){
            //Call the code to send notification to user record as per his preference
            sendNotificationToUsers(new List<String>{request.get(0).ownerid},request);
       }else if(request.get(0).ownerType==OwnerType.QUEUE.name()){
            //Call the code to send notification to all the user records are per their preferences
            sendNotificationToQueue(request.get(0).ownerid,request);
       }
    }//sendNotification Ends

    private static void sendNotificationToQueue(String queueId,List<FlowInputs> request){
        system.debug('Inside sendNotificationToQueue'+queueId);
        List<String> userIds = new List<String>();
        //Fetch the Queue Members. In ourcase queue member is a group. So fetching groupid
        List<GroupMember> queueMembers = [Select UserOrGroupId From GroupMember where GroupId =: queueId];
        system.debug('queueMembers : '+queueMembers);
        for(GroupMember queueMember : queueMembers){
            userIds.add(queueMember.UserOrGroupId);
        }
        system.debug('userIds : '+userIds);
        sendNotificationToUsers(userIds,request);
    }

    private static void sendNotificationToUsers(List<String> userId,List<FlowInputs> request){
        system.debug('Inside sendNotificationToUsers '+userId);
         List<User> usersList = [Select Id,TA_Notification_Type__c,Email,Name from User where ID IN:userId];
        
         Set<String> bellNotificationUsers          = new Set<String>();
         Set<String> emailNotificationUsers         = new Set<String>();
         String targetObjectId = usersList[0].id;
        for(User userRec : usersList){
            if(userRec.TA_Notification_Type__c =='Bell Notification')
            {
               bellNotificationUsers.add(userRec.id);
            }
            else if(userRec.TA_Notification_Type__c =='Email Notification')
            {
               //sendEmailNotification(userRec,request);
               emailNotificationUsers.add(userRec.Email);
            }
            else if(userRec.TA_Notification_Type__c =='Both')
            {
                emailNotificationUsers.add(userRec.Email);
                bellNotificationUsers.add(userRec.id);
               // sendEmailNotification(userRec,request);
            }
        }//for Ends

        if(!emailNotificationUsers.isEmpty()){
            sendEmailNotification(targetObjectId,emailNotificationUsers,request);
        }

        if(!bellNotificationUsers.isEmpty()){
            sendBellNotification(bellNotificationUsers,request);
        }
        
    }

    private static void sendBellNotification(Set<String> userIds,List<FlowInputs> request){
            system.debug('Inside sendBellNotification '+userIds);
            Set <String> recipientsIds = new Set < String >();
            CustomNotificationType notificationType = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = 'TA_User_Notification'];
            
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setTitle(request.get(0).bellTitle);
            notification.setBody(request.get(0).bellBody);
            notification.setTargetId(request.get(0).whatid);
            notification.setNotificationTypeId(notificationType.Id);
            
            
            try {
                notification.send(userIds); 
            }
            catch (Exception e) {
                System.debug('Notification Failed ' + e.getMessage());
            }
        
    }//sendBellNotification
    

    private static void sendEmailNotification(String targetObjectId,Set<String> userEmails,List<FlowInputs> request){
        system.debug('Inside sendEmailNotification '+userEmails);
        List<String> userEmailList = new List<String>();
        userEmailList.addAll(userEmails);
        //Get email template
        Map<String,TA_User_Notification_Type__mdt> notificationTemplate = fetchNotificationMetadata();
        system.debug('notificationTemplate : '+notificationTemplate);

        String emailTemplateName = notificationTemplate.get(request.get(0).contextType).TA_Email_Template__c;
        system.debug('emailTemplateName : '+emailTemplateName);

        EmailTemplate emailTemplate =[Select Id,Subject,Description,HtmlValue,DeveloperName,Body from EmailTemplate where name =: emailTemplateName limit 1 ];
        

        System.debug('Email template : '+emailTemplate);


        Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
        message.setTemplateID(emailTemplate.Id);
        message.setToAddresses(userEmailList);
        message.setWhatId(request.get(0).whatid);
        message.setTargetObjectId(targetObjectId); //THIS IS REQ CAN BE USER /LEAD OR CONTACT Bulkification hit here, when we have to set one targetobjectid
        message.setSaveAsActivity(false);
       
        Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] {message});
        if (results[0].success) {
            System.debug('The email was sent successfully.');
        } else {
            System.debug('The email failed to send: ' + results[0].errors[0].message);
        }

        
    }//sendEmailNotification Ends
  
/*
===============================WRAPPER CLASSES===================================================
*/
    public class FlowInputs{
        @InvocableVariable (label ='What Id' required=true)
        public String whatid;
        
        @InvocableVariable (label ='Bell Title' required=true)
        public String bellTitle;

        @InvocableVariable (label ='Bell Body' required=true)
        public String bellBody;
        
        @InvocableVariable (label ='Context Type' required=true)
        public String contextType;

        @InvocableVariable (label ='Owner Rec' required=true)
        public Id ownerid;
        
        @InvocableVariable (label ='Owner Type' required=true)
        public String ownerType;
        
       

    }
}
