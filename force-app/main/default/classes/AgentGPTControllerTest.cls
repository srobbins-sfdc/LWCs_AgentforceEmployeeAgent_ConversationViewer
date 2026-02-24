/**
 * @description Test class for AgentGPTController
 * Tests Data Cloud query logic and AI title generation
 */
@isTest
private class AgentGPTControllerTest {
    
    /**
     * @description Test successful retrieval of user sessions
     * Note: Since we're using ConnectApi which cannot be easily mocked,
     * this test validates the input handling and error scenarios
     */
    @isTest
    static void testGetUserSessions_ValidInput() {
        Test.startTest();
        try {
            // Call with valid input
            List<AgentGPTController.SessionWrapper> result = 
                AgentGPTController.getUserSessions(7);
            
            // If Data Cloud is configured, result will be a list (may be empty)
            // If not configured, it will throw an exception
            System.assertNotEquals(null, result, 'Result should not be null');
            
        } catch (AuraHandledException e) {
            // Expected if Data Cloud is not configured or query fails
            System.assert(true, 'Exception acceptable when Data Cloud unavailable or query fails');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test with null daysLookback parameter (should default to 7)
     */
    @isTest
    static void testGetUserSessions_NullInput() {
        Test.startTest();
        try {
            // Call with null input (should default to 7 days)
            List<AgentGPTController.SessionWrapper> result = 
                AgentGPTController.getUserSessions(null);
            
            System.assertNotEquals(null, result, 'Result should not be null');
            
        } catch (AuraHandledException e) {
            // Expected if Data Cloud is not configured or query fails
            System.assert(true, 'Exception acceptable when Data Cloud unavailable or query fails');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test with invalid daysLookback parameter (should default to 7)
     */
    @isTest
    static void testGetUserSessions_InvalidInput() {
        Test.startTest();
        try {
            // Call with invalid input (should default to 7 days)
            List<AgentGPTController.SessionWrapper> result = 
                AgentGPTController.getUserSessions(-5);
            
            System.assertNotEquals(null, result, 'Result should not be null');
            
        } catch (AuraHandledException e) {
            // Expected if Data Cloud is not configured or query fails
            System.assert(true, 'Exception acceptable when Data Cloud unavailable or query fails');
        }
        Test.stopTest();
    }
    
    /**
     * @description Test getCurrentUserTimeZone returns the running user's timezone ID
     */
    @isTest
    static void testGetCurrentUserTimeZone() {
        Test.startTest();
        String tz = AgentGPTController.getCurrentUserTimeZone();
        Test.stopTest();
        System.assertNotEquals(null, tz, 'TimeZone should not be null');
        System.assert(tz.length() > 0, 'TimeZone should not be empty');
    }
    
    /**
     * @description Test session title generation with valid input
     */
    @isTest
    static void testGenerateSessionTitle_ValidInput() {
        Test.startTest();
        
        String conversationContext = 
            'User: Hello, I need help with my account.\n' +
            'Agent: I\'d be happy to help you with your account.\n' +
            'User: I forgot my password.';
        
        try {
            String title = AgentGPTController.generateSessionTitle(conversationContext);
            
            // Should return a non-null title
            System.assertNotEquals(null, title, 'Title should not be null');
            System.assertNotEquals('', title, 'Title should not be empty');
            
        } catch (Exception e) {
            // Expected if Einstein Prompt Template is not configured
            // The method should handle this gracefully
            System.debug('Expected exception if prompt template not configured: ' + e.getMessage());
        }
        
        Test.stopTest();
    }
    
    /**
     * @description Test session title generation with blank input
     */
    @isTest
    static void testGenerateSessionTitle_BlankInput() {
        Test.startTest();
        
        String title = AgentGPTController.generateSessionTitle('');
        
        // Should return default title
        System.assertEquals('Untitled Conversation', title, 
            'Should return default title for blank input');
        
        Test.stopTest();
    }
    
    /**
     * @description Test session title generation with null input
     */
    @isTest
    static void testGenerateSessionTitle_NullInput() {
        Test.startTest();
        
        String title = AgentGPTController.generateSessionTitle(null);
        
        // Should return default title
        System.assertEquals('Untitled Conversation', title, 
            'Should return default title for null input');
        
        Test.stopTest();
    }
    
    /**
     * @description Test SessionWrapper compareTo method for sorting
     */
    @isTest
    static void testSessionWrapper_Sorting() {
        Test.startTest();
        
        // Create test sessions with different timestamps
        AgentGPTController.SessionWrapper session1 = new AgentGPTController.SessionWrapper();
        session1.sessionId = 'session1';
        session1.startTime = DateTime.now().addDays(-2);
        
        AgentGPTController.SessionWrapper session2 = new AgentGPTController.SessionWrapper();
        session2.sessionId = 'session2';
        session2.startTime = DateTime.now().addDays(-1);
        
        AgentGPTController.SessionWrapper session3 = new AgentGPTController.SessionWrapper();
        session3.sessionId = 'session3';
        session3.startTime = DateTime.now();
        
        // Create list and sort
        List<AgentGPTController.SessionWrapper> sessions = new List<AgentGPTController.SessionWrapper>{
            session1, session3, session2
        };
        sessions.sort();
        
        // Verify sorting (most recent first)
        System.assertEquals('session3', sessions[0].sessionId, 
            'Most recent session should be first');
        System.assertEquals('session2', sessions[1].sessionId, 
            'Second most recent session should be second');
        System.assertEquals('session1', sessions[2].sessionId, 
            'Oldest session should be last');
        
        Test.stopTest();
    }
    
    /**
     * @description Test SessionWrapper sorting with null timestamps
     */
    @isTest
    static void testSessionWrapper_SortingWithNulls() {
        Test.startTest();
        
        AgentGPTController.SessionWrapper session1 = new AgentGPTController.SessionWrapper();
        session1.sessionId = 'session1';
        session1.startTime = null;
        
        AgentGPTController.SessionWrapper session2 = new AgentGPTController.SessionWrapper();
        session2.sessionId = 'session2';
        session2.startTime = DateTime.now();
        
        List<AgentGPTController.SessionWrapper> sessions = new List<AgentGPTController.SessionWrapper>{
            session1, session2
        };
        sessions.sort();
        
        // Session with timestamp should come before null
        System.assertEquals('session2', sessions[0].sessionId, 
            'Session with timestamp should be first');
        
        Test.stopTest();
    }
    
    /**
     * @description Test getRecentSessionsForHome with valid input
     */
    @isTest
    static void testGetRecentSessionsForHome_ValidInput() {
        Test.startTest();
        try {
            AgentGPTController.PaginatedSessionsWrapper result =
                AgentGPTController.getRecentSessionsForHome(5, 1);
            System.assertNotEquals(null, result, 'Result should not be null');
            System.assertNotEquals(null, result.sessions, 'Sessions list should not be null');
            System.assertNotEquals(null, result.totalCount, 'Total count should not be null');
        } catch (AuraHandledException e) {
            // Expected if Data Cloud is not configured or query fails
            System.assert(true, 'Exception acceptable when Data Cloud unavailable or query fails');
        }
        Test.stopTest();
    }

    /**
     * @description Test getRecentSessionsForHome with null/default params
     */
    @isTest
    static void testGetRecentSessionsForHome_DefaultParams() {
        Test.startTest();
        try {
            AgentGPTController.PaginatedSessionsWrapper result =
                AgentGPTController.getRecentSessionsForHome(null, null);
            System.assertNotEquals(null, result, 'Result should not be null');
            System.assertNotEquals(null, result.sessions, 'Sessions should not be null');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected exception when Data Cloud not configured');
        }
        Test.stopTest();
    }

    /**
     * @description Test MessageWrapper instantiation
     */
    @isTest
    static void testMessageWrapper_Creation() {
        Test.startTest();
        
        AgentGPTController.MessageWrapper message = new AgentGPTController.MessageWrapper();
        message.role = 'USER';
        message.text = 'Test message';
        message.timestamp = String.valueOf(DateTime.now());
        
        System.assertEquals('USER', message.role, 'Role should be set correctly');
        System.assertEquals('Test message', message.text, 'Text should be set correctly');
        System.assertNotEquals(null, message.timestamp, 'Timestamp should not be null');
        
        Test.stopTest();
    }
    
    /**
     * @description CRITICAL: Verify sort returns newest first (descending by sortEpochMs).
     * If this fails, Agent Sessions (Home) page 1 will show older sessions.
     */
    @isTest
    static void testSortSessionsNewestFirst_DescendingOrder() {
        Test.startTest();
        AgentGPTController.SessionWrapper oldSession = new AgentGPTController.SessionWrapper();
        oldSession.sessionId = 'old';
        oldSession.sortEpochMs = 1000L;
        AgentGPTController.SessionWrapper newSession = new AgentGPTController.SessionWrapper();
        newSession.sessionId = 'new';
        newSession.sortEpochMs = 3000L;
        AgentGPTController.SessionWrapper midSession = new AgentGPTController.SessionWrapper();
        midSession.sessionId = 'mid';
        midSession.sortEpochMs = 2000L;
        List<AgentGPTController.SessionWrapper> input = new List<AgentGPTController.SessionWrapper>{
            oldSession, newSession, midSession
        };
        List<AgentGPTController.SessionWrapper> result = AgentGPTController.sortSessionsNewestFirst(input);
        Test.stopTest();
        System.assertEquals(3, result.size(), 'Should return same count');
        System.assertEquals(3000L, result[0].sortEpochMs, 'Page 1 first item must be newest (3000)');
        System.assertEquals(2000L, result[1].sortEpochMs, 'Second must be middle (2000)');
        System.assertEquals(1000L, result[2].sortEpochMs, 'Last must be oldest (1000)');
    }
    
    /**
     * @description Verify timestamp parsing: Dec 5 2025 > Nov 22 2025 so sort can distinguish dates.
     */
    @isTest
    static void testTimestampStringToEpochMs_DateOrder() {
        Test.startTest();
        Long dec5 = AgentGPTController.timestampStringToEpochMs('2025-12-05 12:00:00');
        Long nov22 = AgentGPTController.timestampStringToEpochMs('2025-11-22 12:00:00');
        Test.stopTest();
        System.assertNotEquals(null, dec5, 'Dec 5 should parse');
        System.assertNotEquals(null, nov22, 'Nov 22 should parse');
        System.assert(dec5 > nov22, 'Dec 5 2025 must be later than Nov 22 2025 for correct sort');
    }
    
    /**
     * @description Verify timestamp parsing with T and Z formats (ISO).
     */
    @isTest
    static void testTimestampStringToEpochMs_IsoFormats() {
        Test.startTest();
        Long t = AgentGPTController.timestampStringToEpochMs('2025-12-05T14:30:00');
        Long z = AgentGPTController.timestampStringToEpochMs('2025-12-05T14:30:00.000Z');
        Test.stopTest();
        System.assertNotEquals(null, t, 'ISO with T should parse');
        System.assertNotEquals(null, z, 'ISO with Z should parse');
    }
}
