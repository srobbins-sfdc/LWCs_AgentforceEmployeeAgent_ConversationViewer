import { LightningElement, wire, track } from 'lwc';
import getRecentSessionsForHome from '@salesforce/apex/AgentGPTController.getRecentSessionsForHome';
import getCurrentUserTimeZone from '@salesforce/apex/AgentGPTController.getCurrentUserTimeZone';
import generateSessionTitle from '@salesforce/apex/AgentGPTController.generateSessionTitle';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { renderMessageContent } from 'c/messageFormatter';

const PAGE_SIZE = 5;

export default class AgentSessionsHome extends LightningElement {
    @track sessions = [];
    @track totalCount = 0;
    @track currentPage = 1;
    @track isLoading = true;
    @track error;
    @track selectedSession = null;
    @track showOverlay = false;
    /** User timezone from server (Salesforce user preference); used for session tile and overlay so both match. */
    userTimeZone = null;
    /** Cache of sessionId -> title so Prev/Next don't re-generate titles */
    titleCache = {};

    connectedCallback() {
        this.loadPage(1);
    }

    @wire(getCurrentUserTimeZone)
    wiredTimeZone({ data }) {
        if (data) {
            this.userTimeZone = data;
            this.refreshSessionTileTimes(data);
        }
    }

    /** Re-format session tile date/time when timezone becomes available (fixes tile showing UTC). */
    refreshSessionTileTimes(timeZoneOverride) {
        const tz = timeZoneOverride !== undefined ? timeZoneOverride : this.userTimeZone;
        if (!this.sessions || this.sessions.length === 0 || !tz) return;
        this.sessions = this.sessions.map(s => {
            const displayTime = this.getSessionDisplayTime(s);
            const formattedStartTime = displayTime ? this.formatStartTimeFromDate(displayTime, tz) : '';
            const formattedDate = displayTime ? this.formatDateFromDate(displayTime, tz) : '';
            return {
                ...s,
                formattedDate,
                formattedStartTime,
                hasStartTime: !!formattedStartTime
            };
        });
    }

    get hasSessions() {
        return this.sessions && this.sessions.length > 0;
    }

    get hasPrevPage() {
        return this.currentPage > 1;
    }

    get hasNextPage() {
        const totalPages = Math.ceil(this.totalCount / PAGE_SIZE) || 0;
        return this.currentPage < totalPages;
    }

    get prevButtonDisabled() {
        return !this.hasPrevPage;
    }

    get nextButtonDisabled() {
        return !this.hasNextPage;
    }

    get pageInfo() {
        if (this.totalCount === 0) return 'No conversations';
        const start = (this.currentPage - 1) * PAGE_SIZE + 1;
        const end = Math.min(this.currentPage * PAGE_SIZE, this.totalCount);
        return `${start}–${end} of ${this.totalCount}`;
    }

    get overlaySessionTitle() {
        return (this.selectedSession && this.selectedSession.title) || 'Conversation';
    }

    get hasOverlayMessages() {
        return this.selectedSession && this.selectedSession.messages && this.selectedSession.messages.length > 0;
    }

    get overlayProcessedMessages() {
        if (!this.selectedSession || !this.selectedSession.messages) return [];
        return this.processMessagesForOverlay(this.selectedSession.messages, this.selectedSession.agentName);
    }

    /**
     * Browser timezone fallback when server does not send user timezone.
     */
    get browserTimeZone() {
        try {
            return Intl.DateTimeFormat().resolvedOptions().timeZone || undefined;
        } catch (e) {
            return undefined;
        }
    }

    /**
     * Timezone to use for all date/time formatting (server user timezone preferred so session tile and overlay match).
     */
    get effectiveTimeZone() {
        return this.userTimeZone || this.browserTimeZone;
    }

    /**
     * Get the best available datetime for a session (first message time if startTime missing/unparseable)
     */
    getSessionDisplayTime(session) {
        const fromStart = this.parseSessionDate(session.startTime);
        if (fromStart) return fromStart;
        const firstMsg = session.messages && session.messages.length > 0 ? session.messages[0] : null;
        const fromMsg = firstMsg ? this.parseSessionDate(firstMsg.timestamp) : null;
        return fromMsg || null;
    }

    /**
     * Parse Apex DateTime or timestamp string to Date (handles ISO, space-separated, number)
     */
    parseSessionDate(val) {
        if (val == null || val === '') return null;
        try {
            if (typeof val === 'number') {
                const d = new Date(val);
                return isNaN(d.getTime()) ? null : d;
            }
            const str = String(val).trim();
            if (!str) return null;
            const normalized = str.indexOf(' ') !== -1 && str.indexOf('T') === -1 ? str.replace(' ', 'T') : str;
            const d = new Date(normalized);
            return isNaN(d.getTime()) ? null : d;
        } catch (e) {
            return null;
        }
    }

    async loadPage(pageNumber) {
        this.isLoading = true;
        this.error = undefined;
        try {
            const result = await getRecentSessionsForHome({
                pageSize: PAGE_SIZE,
                pageNumber: pageNumber
            });
            this.userTimeZone = result.userTimeZone || this.userTimeZone;
            const tz = result.userTimeZone || this.userTimeZone || this.browserTimeZone;
            // Use server order only (Apex sortSessionsNewestFirst); no client re-sort so sort is deterministic
            let list = result.sessions || [];
            this.sessions = list.map(s => {
                const displayTime = this.getSessionDisplayTime(s);
                const formattedStartTime = displayTime ? this.formatStartTimeFromDate(displayTime, tz) : '';
                const formattedDate = displayTime ? this.formatDateFromDate(displayTime, tz) : '';
                const cachedTitle = this.titleCache[s.sessionId];
                return {
                    ...s,
                    title: cachedTitle || s.title,
                    formattedDate,
                    formattedStartTime,
                    hasStartTime: !!formattedStartTime,
                    cssClass: 'slds-list__item session-item'
                };
            });
            this.totalCount = result.totalCount || 0;
            this.currentPage = pageNumber;
            if (this.userTimeZone) this.refreshSessionTileTimes();
            this.generateMissingTitles();
        } catch (e) {
            this.error = this.reduceErrors(e);
            this.sessions = [];
            this.totalCount = 0;
            this.showError('Error loading conversations: ' + this.error);
        } finally {
            this.isLoading = false;
        }
    }

    async generateMissingTitles() {
        const needingTitles = this.sessions.filter(
            s => !this.titleCache[s.sessionId] && s.title === 'Loading...' && s.messages && s.messages.length > 0
        );
        for (const session of needingTitles) {
            try {
                const contextMessages = session.messages.slice(0, 3);
                const conversationContext = contextMessages
                    .map(msg => {
                        const role = (msg.role || '').toUpperCase();
                        const label = (role === 'USER' || role === 'ENDUSER') ? 'You' : (session.agentName || 'Agent');
                        return `${label}: ${msg.text}`;
                    })
                    .join('\n');
                const generatedTitle = await generateSessionTitle({ conversationContext });
                if (generatedTitle && generatedTitle !== 'Loading...') {
                    this.titleCache[session.sessionId] = generatedTitle;
                    const idx = this.sessions.findIndex(s => s.sessionId === session.sessionId);
                    if (idx !== -1) {
                        this.sessions[idx].title = generatedTitle;
                        this.sessions = [...this.sessions];
                    }
                }
            } catch (err) {
                this.titleCache[session.sessionId] = 'Untitled Conversation';
                const idx = this.sessions.findIndex(s => s.sessionId === session.sessionId);
                if (idx !== -1) this.sessions[idx].title = 'Untitled Conversation';
                this.sessions = [...this.sessions];
            }
        }
    }

    formatDate(dateTimeVal) {
        const date = this.parseSessionDate(dateTimeVal);
        return date ? this.formatDateFromDate(date) : (dateTimeVal != null ? String(dateTimeVal) : '');
    }

    formatDateFromDate(date, timeZoneOverride) {
        if (!date || isNaN(date.getTime())) return '';
        const tz = timeZoneOverride !== undefined ? timeZoneOverride : this.effectiveTimeZone;
        const today = new Date();
        const yesterday = new Date(today);
        yesterday.setDate(yesterday.getDate() - 1);
        const opts = tz ? { timeZone: tz } : {};
        if (this.isSameDay(date, today, tz)) return 'Today';
        if (this.isSameDay(date, yesterday, tz)) return 'Yesterday';
        const showYear = tz
            ? date.toLocaleDateString('en-CA', { ...opts, year: 'numeric' }) !== today.toLocaleDateString('en-CA', { ...opts, year: 'numeric' })
            : date.getFullYear() !== today.getFullYear();
        return date.toLocaleDateString('en-US', {
            ...opts,
            month: 'short',
            day: 'numeric',
            year: showYear ? 'numeric' : undefined
        });
    }

    formatStartTime(dateTimeVal) {
        const date = this.parseSessionDate(dateTimeVal);
        return date ? this.formatStartTimeFromDate(date) : '';
    }

    formatStartTimeFromDate(date, timeZoneOverride) {
        if (!date || isNaN(date.getTime())) return '';
        const tz = timeZoneOverride !== undefined ? timeZoneOverride : this.effectiveTimeZone;
        
        // Build options object directly (avoid spread which might cause issues in Locker Service)
        const options = {
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
        };
        if (tz) {
            options.timeZone = tz;
        }
        
        return date.toLocaleTimeString('en-US', options);
    }

    formatTime(timestamp) {
        if (!timestamp) return '';
        try {
            const date = new Date(timestamp);
            const opts = this.effectiveTimeZone ? { timeZone: this.effectiveTimeZone } : {};
            return date.toLocaleTimeString('en-US', {
                ...opts,
                month: 'short',
                day: 'numeric',
                hour: 'numeric',
                minute: '2-digit',
                hour12: true
            });
        } catch (e) {
            return String(timestamp);
        }
    }

    isSameDay(d1, d2, timeZoneOverride) {
        if (!d1 || !d2 || isNaN(d1.getTime()) || isNaN(d2.getTime())) return false;
        const tz = timeZoneOverride !== undefined ? timeZoneOverride : this.effectiveTimeZone;
        if (tz) {
            const opts = { timeZone: tz };
            return d1.toLocaleDateString('en-CA', opts) === d2.toLocaleDateString('en-CA', opts);
        }
        return d1.getDate() === d2.getDate() &&
               d1.getMonth() === d2.getMonth() &&
               d1.getFullYear() === d2.getFullYear();
    }

    processMessagesForOverlay(messages, agentName) {
        if (!messages) return [];
        return messages.map((msg, idx) => {
            const role = (msg.role || '').toUpperCase();
            const isUser = role === 'USER' || role === 'ENDUSER';
            const roleLabel = isUser ? 'You' : (agentName || 'Agentforce AI');
            return {
                key: (msg.timestamp || '') + idx,
                text: msg.text,
                renderedContent: renderMessageContent(msg.text),
                formattedTime: this.formatTime(msg.timestamp),
                roleLabel,
                isUser,
                wrapperClass: 'message-row'
            };
        });
    }

    handlePrev() {
        if (this.hasPrevPage) this.loadPage(this.currentPage - 1);
    }

    handleNext() {
        if (this.hasNextPage) this.loadPage(this.currentPage + 1);
    }

    handleSessionClick(event) {
        const sessionId = event.currentTarget.dataset.sessionId;
        const session = this.sessions.find(s => s.sessionId === sessionId);
        if (session) {
            this.selectedSession = { ...session };
            this.showOverlay = true;
        }
    }

    handleCloseOverlay() {
        this.showOverlay = false;
        this.selectedSession = null;
    }

    handleOverlayModalClick(event) {
        event.stopPropagation();
    }

    showError(message) {
        this.dispatchEvent(new ShowToastEvent({
            title: 'Error',
            message,
            variant: 'error'
        }));
    }

    reduceErrors(errors) {
        if (!errors) return 'Unknown error';
        if (Array.isArray(errors)) {
            return errors.filter(e => !!e).map(e => e.message || e.body?.message || 'Unknown error').join(', ');
        }
        if (typeof errors === 'string') return errors;
        if (errors.body?.message) return errors.body.message;
        if (errors.body?.pageErrors?.length) return errors.body.pageErrors[0].message;
        return errors.message || errors.statusText || 'Unknown error';
    }
}
