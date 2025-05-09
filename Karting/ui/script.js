$(function() {
    // Variables
    let displayed = false;
    
    // Event listeners for UI buttons
    $('.close-btn, #close-btn').click(function() {
        closeMenu();
    });
    
    // Event listener for ESC key
    $(document).keyup(function(e) {
        if (e.keyCode === 27 && displayed) { // ESC key
            closeMenu();
        }
    });
    
    // Event listener for rent buttons
    $('.rent-btn').click(function() {
        const sessionType = $(this).data('type');
        
        // Ha előfizetői mód, azonnal elküldjük
        if (sessionType === 'subscriber') {
            $.post('https://Karting/purchaseSession', JSON.stringify({
                type: sessionType
            }));
            return;
        }
        
        // Fizetési mód választó megjelenítése
        const paymentMethodHtml = `
            <div id="payment-method-modal">
                <div class="payment-content">
                    <h2>Fizetési mód kiválasztása</h2>
                    <div class="payment-options">
                        <button class="payment-option cash" data-method="cash">
                            <i class="fa fa-money"></i>
                            <span>Készpénz</span>
                        </button>
                        <button class="payment-option bank" data-method="bank">
                            <i class="fa fa-credit-card"></i>
                            <span>Bankkártya</span>
                        </button>
                    </div>
                    <button class="payment-cancel">Mégsem</button>
                </div>
            </div>
        `;
        
        // Hozzáadjuk a modalt a bodyhoz
        $('body').append(paymentMethodHtml);
        
        // Megjelenítjük a modalt
        $('#payment-method-modal').fadeIn(200);
        
        // Fizetési mód választása
        $('.payment-option').click(function() {
            const paymentMethod = $(this).data('method');
            $('#payment-method-modal').fadeOut(200, function() {
                $(this).remove();
                
                // Küldjük a vásárlási kérelmet a szervernek a fizetési móddal együtt
                $.post('https://Karting/purchaseSession', JSON.stringify({
                    type: sessionType,
                    paymentMethod: paymentMethod
                }));
            });
        });
        
        // Mégsem gomb
        $('.payment-cancel').click(function() {
            $('#payment-method-modal').fadeOut(200, function() {
                $(this).remove();
            });
        });
    });
    
    // Function to close the menu
    function closeMenu() {
        $('#karting-container').fadeOut(300);
        $.post('https://Karting/closeMenu', JSON.stringify({}));
        displayed = false;
    }
    
    // Function to update price and duration
    function updateInfo(data) {
        if (data.price) {
            $('#price').text(data.price);
        }
        
        if (data.duration) {
            $('#duration').text(data.duration);
        }
        
        // Handle subscription information
        if (data.isSubscriber === true) {
            $('.subscription-status').remove();
            $('.quick-rent').remove();
            
            // Add subscription status
            let subscriptionHtml = `
                <div class="subscription-status">
                    <h3>Aktív előfizetés</h3>
                    <p>Előfizetésed érvényes: ${data.expiryDate}</p>
                    <p>Használd a G gombot az azonnali kartingozáshoz az NPC közelében!</p>
                </div>
            `;
            
            $('.info-section').append(subscriptionHtml);
            
        } else {
            $('.subscription-status').remove();
        }
        
        // Add best laptime information if available
        if (data.laptimes) {
            $('.laptime-info').remove();
            
            let laptimeHtml = `
                <div class="laptime-info">
                    <h3>Legjobb köridők</h3>
                    <div class="laptime-tables">
                        <div class="laptime-table">
                            <h4>Mai legjobb</h4>
                            <ul class="laptime-list daily-best">
                                ${generateLaptimesList(data.laptimes.daily)}
                            </ul>
                        </div>
                        <div class="laptime-table">
                            <h4>Havi legjobb</h4>
                            <ul class="laptime-list monthly-best">
                                ${generateLaptimesList(data.laptimes.monthly)}
                            </ul>
                        </div>
                        <div class="laptime-table">
                            <h4>Éves legjobb</h4>
                            <ul class="laptime-list yearly-best">
                                ${generateLaptimesList(data.laptimes.yearly)}
                            </ul>
                        </div>
                    </div>
                </div>
            `;
            
            $('.options-section').before(laptimeHtml);
        }
        
        // Session results if available
        if (data.sessionResults) {
            showSessionResults(data.sessionResults);
        }
    }
    
    function generateLaptimesList(laptimes) {
        if (!laptimes || laptimes.length === 0) {
            return '<li class="no-record">Nincs rögzített köridő</li>';
        }
        
        let html = '';
        laptimes.slice(0, 10).forEach((laptime, index) => {
            html += `<li class="laptime-item ${index < 3 ? 'top-three' : ''}">
                <span class="rank">${index + 1}.</span>
                <span class="name">${laptime.name}</span>
                <span class="time">${formatTime(laptime.time)}</span>
            </li>`;
        });
        
        return html;
    }
    
    function formatTime(ms) {
        const totalSeconds = ms / 1000;
        const minutes = Math.floor(totalSeconds / 60);
        const seconds = Math.floor(totalSeconds % 60);
        const milliseconds = Math.floor((totalSeconds - Math.floor(totalSeconds)) * 1000);
        
        return `${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')}.${milliseconds.toString().padStart(3, '0')}`;
    }
    
    function showSessionResults(results) {
        // Create a modal for session results
        const modalHtml = `
            <div id="results-modal">
                <div class="results-content">
                    <h2>Gokart Menet Eredmények</h2>
                    <div class="results-info">
                        <p><strong>Megtett körök:</strong> ${results.laps}</p>
                        <p><strong>Teljes idő:</strong> ${formatTime(results.totalTime)}</p>
                        <p><strong>Legjobb köridő:</strong> ${formatTime(results.bestLap)}</p>
                        <p><strong>Átlagos köridő:</strong> ${formatTime(results.avgLap)}</p>
                    </div>
                    <div class="lap-breakdown">
                        <h3>Körök részletezése</h3>
                        <ul class="lap-list">
                            ${results.lapTimes.map((time, index) => `
                                <li class="lap-item ${time === results.bestLap ? 'best-lap' : ''}">
                                    <span class="lap-number">Kör ${index + 1}</span>
                                    <span class="lap-time">${formatTime(time)}</span>
                                </li>
                            `).join('')}
                        </ul>
                    </div>
                    <div class="close-instructions">
                        <p>Kattints az alábbi gombra vagy nyomd meg az ESC billentyűt a bezáráshoz</p>
                    </div>
                    <button id="close-results" class="btn close-btn-large">Bezárás</button>
                </div>
            </div>
        `;
        
        // Remove existing modal if any
        $('#results-modal').remove();
        
        // Add modal to the body
        $('body').append(modalHtml);
        
        // Show modal
        $('#results-modal').fadeIn(300);
        
        // Villogtassuk a bezárási utasítást a jobb láthatóság érdekében
        let flashInterval = setInterval(function() {
            $('.close-instructions').fadeOut(500).fadeIn(500);
        }, 1000);
        
        // Függvény az eredmények bezárására
        function closeResults() {
            clearInterval(flashInterval);
            $('#results-modal').fadeOut(300, function() {
                $(this).remove();
                // Késleltetjük a callback-et, hogy a UI animáció befejeződhessen
                setTimeout(function() {
                    $.post('https://Karting/closeResults', JSON.stringify({}));
                }, 100);
            });
        }
        
        // Close button event
        $('#close-results').click(closeResults);
        
        // ESC billentyű kezelése az eredményekhez
        $(document).keyup(function(e) {
            if (e.keyCode === 27 && $('#results-modal').is(':visible')) { // ESC key
                closeResults();
            }
        });
    }
    
    // Event listener for NUI messages from the client script
    window.addEventListener('message', function(event) {
        const data = event.data;
        
        if (data.type === 'open') {
            $('#karting-container').css('display', 'flex').fadeIn(300);
            displayed = true;
            updateInfo(data);
        } else if (data.type === 'close') {
            closeMenu();
        } else if (data.type === 'sessionResults') {
            showSessionResults(data.results);
        } else if (data.type === 'update') {
            updateInfo(data);
        }
    });
}); 