local gamblerNumeroUno = CreateLambdaConvar( "lambdaplayers_poker_enabled", 1, true, false, false, "If Lambda Players are allowed to use and play GPoker.", 0, 1, { type = "Bool", name = "Allow Playing GPoker", category = "Lambda Server Settings" } )
local gambleAddiction = CreateLambdaConvar( "lambdaplayers_poker_alwaysfindtables", 1, true, false, false, "If Lambda Players should always look for open GPoker tables.", 0, 1, { type = "Bool", name = "Always Look For GPoker Tables", category = "Lambda Server Settings" } )

--

local function InitializeModule()
    if !gPoker then return end
    LambdaGPokerInitialized = true

    local IsValid = IsValid
    local Entity = Entity
    local Clamp = math.Clamp
    local floor = math.floor
    local pow = math.pow
    local net = net
    local pairs = pairs
    local CurTime = CurTime
    local Angle = Angle
    local Vector = Vector
    local FindByClass = ents.FindByClass
    local ConVarExists = ConVarExists
    local PrintMessage = PrintMessage
    local table_remove = table.remove
    local table_Copy = table.Copy
    local table_IsEmpty = table.IsEmpty
    local table_Empty = table.Empty
    local table_HasValue = table.HasValue
    local ipairs = ipairs
    local Rand = math.Rand
    local random = math.random
    local RandomPairs = RandomPairs
    local istable = istable
    local SimpleTimer = timer.Simple
    local sound_Play = sound.Play
    local nextWarningT = 0

    --

    local function GetHealthBet( ply )
        if ply.IsLambdaPlayer then
            if ( CLIENT ) then 
                local nwHP = ply:GetNW2Float( "lambda_health", false )
                if nwHP == false then nwHP = ply:GetNWFloat( "lambda_health", ply:GetMaxHealth() ) end
                return nwHP
            end

            return ply:Health()
        elseif ply:IsPlayer() then
            return ply:Health()
        else
            local ent = gPoker.getTableFromPlayer( ply )
            if !IsValid( ent ) then return 0 end

            local key = ent:getPlayerKey( ply )
            return ent.players[ key ].health
        end
    end

    local function AddHealthBet( ply, bet, tbl )
        if ( CLIENT ) then return end
        if !IsValid( ply ) then return end
        bet = ( bet or 0 )

        local hp = ( gPoker.betType[ tbl:GetBetType() ].get( ply ) + bet )
        if hp < 1 then 
            local isLambda = ply.IsLambdaPlayer
            local chair = ply:GetVehicle()
            tbl:removePlayerFromMatch( ply, isLambda )

            if isLambda or ply:IsPlayer() then ply:Kill() end
            if isLambda and IsValid( chair ) then chair:Remove() end
        else
            if ply.IsLambdaPlayer or ply:IsPlayer() then 
                ply:SetHealth( hp ) 
            else 
                tbl.players[ e:getPlayerKey( ply ) ].health = hp 
                tbl:updatePlayersTable() 
            end
        end

        tbl:SetPot( tbl:GetPot() - bet )
    end

    gPoker.betType[ 1 ].get = GetHealthBet
    gPoker.betType[ 1 ].add = AddHealthBet

    --

    local function OnLambdaLeaveMatch( lambda )
        lambda.l_PlayingPoker = false
        lambda.l_PokerTable = NULL
        lambda:PreventWeaponSwitch( false )

        local rndAction = lambda.l_PokerQuitAction
        if rndAction == 1 then
            lambda:SetState( "FindTarget" )
        elseif rndAction == 2 then
            lambda:RetreatFrom( self )
        else
            lambda:SetState()
        end

        lambda.l_NextPokerTableCheck = ( CurTime() + random( 20, 45 ) )
    end

    --

    local function LambdaSetTurnFunction( ent, name, old, new )
        if new == 0 then return end

        local state = ent:GetGameState()
        if state < 1 then return end

        local ply = Entity( ent.players[ new ].ind )
        if !IsValid( ply ) then ent:nextTurn() return end

        if gPoker.gameType[ ent:GetGameType() ].states[ state ].drawing then
            if ply.IsLambdaPlayer then 
                local cards = table_Copy( ent.decks[ new ] )
                for _, v in pairs( ent.communityDeck ) do if v.reveal then cards[ #cards + 1 ] = v end end

                local st, vl = ent:getDeckValue( cards )
                local proceedTime = ( random( 5, 50 ) * 0.1 )

                local suits, ranks = {}, {}
                for i = 0, 12 do
                    if i < 4 then suits[ i ] = 0 end
                    ranks[ i ] = 0
                end
                for _, v in pairs( ent.decks[ new ] ) do
                    suits[ v.suit ] = ( suits[ v.suit ] + 1 )
                    ranks[ v.rank ] = ( ranks[ v.rank ] + 1 )
                end

                local picked = {}
                local chance = random( 0, 100 )
                local minChance, highCard
                for i = 12, 0, -1 do if ranks[ i ] > 0 then highCard = i break end end

                if st == 0 or st == 1 or st == 3 then
                    local minSuits = random( 2, 4 )

                    for i = 0, 3 do
                        if suits[i] < minSuits then continue end
                        minChance = ( 65 * ( 0.5 - suits[ i ] * 0.1 ) * ( st + 1 ) )
                        
                        if chance <= minChance then continue end
                        for k, v in pairs( ent.decks[ new ] ) do if v.suit != i then picked[ #picked + 1 ] = k end end
                        
                        break
                    end

                    if table_IsEmpty( picked ) and st != 3  then
                        local minSeq = random( 3, 4 )
                        local seq = 0
                        local cardSeq = {}
                        local pair = false

                        for i = 0, 12 do
                            if ranks[ i ] > 0 then 
                                seq = ( seq + 1 ) 
                                if ranks[ i ] > 1 then pair = i end
                                cardSeq[ #cardSeq + 1 ] = i 
                            elseif seq > 0 then 
                                seq = 0
                                table_Empty( cardSeq )
                            end
                        end

                        if seq >= minSeq then
                            minChance = ( 75 * ( 0.6 - seq * 0.1 ) + ( st + 1 ) )

                            if chance > minChance then
                                for k, v in pairs( ent.decks[ new ] ) do
                                    if table_HasValue( cardSeq, v.rank ) then
                                        if pair and pair == v.rank then
                                            pair = false
                                            picked[ #picked + 1 ] = k
                                        end
                                    else
                                        picked[ #picked + 1 ] = k
                                    end
                                end
                            end
                        end
                    end

                    if table_IsEmpty( picked ) then
                        if st == 0 then
                            minChance = ( highCard >= 6 and 0 or ( random( 15 ) * ( highCard * 0.5 ) ) )

                            for k, v in pairs( ent.decks[ new ] ) do
                                if v.rank == highCard then 
                                    if chance > minChance then picked[ #picked + 1 ] = k end
                                else
                                    picked[ #picked + 1 ] = k
                                end
                            end
                        else
                            local set
                            local keptCard = false

                            for i = 0, 12 do if ranks[ i ] > 1 then set = i break end end
                            minChance = ( random( 15 ) * set )

                            for k, v in pairs( ent.decks[ new ] ) do
                                if v.rank == set or chance > minChance then continue end
                                picked[ #picked + 1 ] = k
                            end
                        end
                    end
                end

                local curState = ent:GetGameState()
                SimpleTimer( proceedTime, function()
                    if !IsValid( ent ) or curState != ent:GetGameState() or ent:GetTurn() != new then return end

                    if ent.decks[ new ] and !table_IsEmpty( picked ) then
                        local old = picked
                        for _, v in pairs( picked ) do ent:dealSingularCard( new, v ) end
                        for _, v in pairs( old ) do ent.deck[ ent.decks[ new ][ v ].suit ][ ent.decks[ new ][ v ].rank ] = true end
                        sound_Play( "gpoker/cardthrow.wav", ent:GetPos() )
                    end
                    if ent.players[ new ] then ent.players[ new ].ready = true end

                    ent:updatePlayersTable()
                    ent:proceed()
                end )
            elseif ent.players[ new ].bot then 
                ent:simulateBotExchange( new ) 
            else
                net.Start( "gpoker_derma_exchange" )
                    net.WriteEntity( ent )
                net.Send( ply )
            end

            return
        end

        if ply.IsLambdaPlayer then
            local cards = table_Copy( ent.decks[ new ] )
            for _, v in pairs( ent.communityDeck ) do if v.reveal then cards[ #cards + 1 ] = v end end

            local st, vl = ent:getDeckValue( cards )
            local proceedTime = ( random( 5, 50 ) * 0.1 )
            local plyEnt = Entity( ent.players[ new ].ind )
            local curState = ent:GetGameState()

            if ent:GetCheck() then
                local minCheckChance = random( 80 * ( st * 0.1 + vl * 0.01 + 0.1 ), 100 )
                local chance = random( 0, 100 )

                if chance >= minCheckChance or gPoker.betType[ ent:GetBetType() ].get( plyEnt ) < 1 then
                    SimpleTimer( proceedTime, function() 
                        if !IsValid( ent ) or curState != ent:GetGameState() or ent:GetTurn() != new then return end

                        if ent.players[ new ] then ent.players[ new ].ready = true end
                        sound_Play( "gpoker/check.wav", ent:GetPos() ) 

                        ent:updatePlayersTable()
                        ent:proceed()
                    end )
                else
                    local val = Clamp( floor( gPoker.betType[ ent:GetBetType() ].get( plyEnt ) * ( random( 5, 50 ) * 0.01 ) * ( st * ( random( 5 ) * 0.1 ) + 0.1 ) ), random( 5 ), 999999999999 )

                    SimpleTimer( proceedTime, function() 
                        if !IsValid( ent ) or curState != ent:GetGameState() or ent:GetTurn() != new then return end

                        if ent.players[ new ] then gPoker.betType[ ent:GetBetType() ].add( plyEnt, -val, ent ) end
                        ent:SetCheck( false )
                        ent:SetBet( val )

                        if ent.players[ new ] then ent.players[ new ].paidBet = val end
                        for _, v in pairs( ent.players ) do if !v.fold then v.ready = false end end

                        sound_Play( "mvm/mvm_money_pickup.wav", ent:GetPos() ) 
                        if ent.players[ new ] then ent.players[ new ].ready = true end

                        ent:updatePlayersTable()
                        ent:proceed()
                    end )
                end
            else
                local bet = ent:GetBet()
                local botValue = gPoker.betType[ ent:GetBetType() ].get( plyEnt )

                local callChance = ( ( ( pow( 2 * botValue, 1.5 ) ) * pow( ( st + 1 ), 2 ) * ( 100 / ( 10 * ( bet + 1 ) ) ) ) / 100 * random( 5 ) )
                local foldChance = ( ( ( 0.5 * botValue) * pow( 0.35 * ( bet + 1 ), 2 ) * ( 100 / ( 14000 * ( 0.5 * ( st + 1 ) ) ) ) ) / 100 * Clamp( ( curState * ( random( 10, 20 ) * 0.1 ) ) / #gPoker.gameType[ ent:GetGameType() ].states, 0.1, 1.2 ) * random( 5 ) )
                local raiseChance = ( ( ( pow( 2 * botValue, 1.5 ) ) * pow( ( st + 1 ), 2 ) * ( 100 / ( 25 * ( bet + 1 ) ) ) ) / 100 * random( 5 ) )

                local canRaise = ( botValue > bet )

                SimpleTimer( proceedTime, function()
                    if !IsValid( ent ) or curState != ent:GetGameState() or ent:GetTurn() != new then return end

                    if foldChance > callChance and ( ( callChance > raiseChance and canRaise ) or true ) then
                        if ent.players[ new ] then ent.players[ new ].fold = true end
                    elseif canRaise and raiseChance > callChance and raiseChance > foldChance then
                        local val = ( ent:GetBet() + floor( gPoker.betType[ ent:GetBetType() ].get( plyEnt ) * 0.1 * ( st * ( random( 5 ) * 0.1 ) + 0.1 ) ) )

                        gPoker.betType[ ent:GetBetType() ].add( plyEnt, -val, ent )
                        if ent.players[ new ] then ent.players[ new ].paidBet = val end

                        for _, v in pairs( ent.players ) do if !v.fold then v.ready = false end end
                        ent:SetBet( val )
                        sound_Play( "mvm/mvm_money_pickup.wav", ent:GetPos() )

                    else
                        if ent.players[ new ] then gPoker.betType[ ent:GetBetType() ].add( plyEnt, -( ent:GetBet() - ent.players[ new ].paidBet ), ent ) end
                        if ent.players[ new ] then ent.players[ new ].paidBet = ent:GetBet() end
                        sound_Play( "mvm/mvm_money_pickup.wav", ent:GetPos() )
                    end

                    if ent.players[ new ] then ent.players[ new ].ready = true end
                    ent:updatePlayersTable()

                    SimpleTimer( 0.2, function()
                        if !IsValid( ent ) or curState != ent:GetGameState() or ent:GetTurn() != new then return end                        
                        ent:proceed()
                    end )
                end )
            end

            return
        end

        if ent.players[ new ].bot then
            ent:simulateBotAction( new ) 
            return 
        end

        net.Start( "gpoker_derma_bettingActions", false )
            net.WriteEntity( ent )
            net.WriteBool( ent:GetCheck() )
            net.WriteFloat( ent:GetBet() )
        net.Send( ply )
    end

    local function LambdaRemoveFromMatch( self, ply, lambdaKill )
        local isLambda = ply.IsLambdaPlayer
        if !isLambda and !ply:IsPlayer() then 
            self:removeBot( ply ) 
            return 
        end

        local key = self:getPlayerKey( ply )
        if key == nil then return end

        if !lambdaKill then
            local chair = ply:GetVehicle()
            ply:ExitVehicle()
            if IsValid( chair ) then chair:Remove() end
        end

        if isLambda then
            OnLambdaLeaveMatch( ply )

            if self:GetTurn() == key and #self.players > 0 then
                self:nextTurn()
            end
        end

        for _, deck in pairs( self.decks[ key ] ) do
            if IsValid( Entity( deck.ind ) ) then Entity( deck.ind ):Remove() end
        end

        table_remove( self.players, key )
        table_remove( self.decks, key )

        self:updateSeatsPositioning()
        self:updateDecksPositioning()
        self:updatePlayersTable()

        if !isLambda and self:GetTurn() == key and #self.players > 0 then
            self:nextTurn()
        end
        
        if self:GetDealer() == key and #self.players > 0 then
            self:nextDealer()
        else
            self:SetDealer( self:GetDealer() )
        end

        if self:getPlayersAmount() < 1 or #self.players <= 1 then 
            if #self.players > 0 then
                local lastPlayer = nil
                for k, v in pairs( self.players ) do
                    if !v.bot then lastPlayer = k break end
                end
                if lastPlayer != nil then gPoker.betType[ self:GetBetType() ].add( Entity( self.players[ lastPlayer ].ind ), self:GetPot(), self ) end
            end
            
            self:prepareForRestart() 
        end
    end

    local function LambdaRevealCommunityCards( self, cards )
        local revealTime = 0.5
        local multiple = istable( cards )
        local finishReveal = revealTime
        local selfPos = self:GetPos()

        if multiple then
            finishReveal = ( finishReveal * #cards )

            for k, v in pairs( cards ) do
                SimpleTimer( ( revealTime * ( k - 1 ) ), function()
                    if !IsValid( self ) or self:GetGameState() < 1 then return end

                    local card = Entity( self.communityDeck[ v ].ind )
                    if !IsValid( card ) then return end
                    
                    local ang = card:GetLocalAngles()
                    card:SetLocalAngles( Angle( ang.p, ang.y, 0 ) )
                    card:SetLocalPos( card:GetLocalPos() * 0.98 )

                    card:SetRank( self.communityDeck[ v ].rank )
                    card:SetSuit( self.communityDeck[ v ].suit )

                    self.communityDeck[ v ].reveal = true
                    sound_Play( "gpoker/cardthrow.wav", selfPos )

                    local clientCopy = table_Copy( self.communityDeck )
                    for i = #clientCopy, 1, -1 do if !clientCopy[ i ].reveal then table_remove( clientCopy, i ) end end

                    for _, v in pairs( self.players ) do
                        if v.bot then continue end

                        local ply = Entity( v.ind )
                        if !ply:IsPlayer() then continue end

                        net.Start( "gpoker_sendDeck", false )
                            net.WriteEntity( self )
                            net.WriteBool( true )
                            net.WriteTable( clientCopy )
                        net.Send( ply )
                    end
                end)
            end
        else
            local card = Entity( self.communityDeck[ cards ].ind )
            if !IsValid( card ) then return end
                
            local ang = card:GetLocalAngles()
            ang:RotateAroundAxis( ang:Forward(), 180 )

            card:SetLocalAngles( ang )
            card:SetLocalPos( card:GetLocalPos() * 0.98 )

            card:SetRank( self.communityDeck[ cards ].rank )
            card:SetSuit( self.communityDeck[ cards ].suit )

            self.communityDeck[ cards ].reveal = true
            sound_Play( "gpoker/cardthrow.wav", selfPos )

            local clientCopy = table_Copy( self.communityDeck )
            for i = #clientCopy, 1, -1 do if !clientCopy[ i ].reveal then table_remove( clientCopy, i ) end end

            for _, v in pairs( self.players ) do
                if v.bot then continue end

                local ply = Entity( v.ind )
                if !ply:IsPlayer() then continue end

                net.Start( "gpoker_sendDeck", false )
                    net.WriteEntity( self )
                    net.WriteBool( true )
                    net.WriteTable( clientCopy )
                net.Send( ply )
            end
        end

        SimpleTimer( ( finishReveal + revealTime ), function()
            if !IsValid( self ) or self:GetGameState() < 1 then return end
            self:nextState()
        end )
    end

    local function LambdaEntryFee( self )
        for k, v in pairs( self.players ) do
            v.ready = false

            local plyEnt = ( v.ind and Entity( v.ind ) )
            if plyEnt and plyEnt:IsPlayer() then
                net.Start( "gpoker_payEntry", false )
                    net.WriteEntity( self )
                net.Send( Entity( v.ind ) )
            
                continue
            end

            SimpleTimer( ( random( 5, ( ( plyEnt and plyEnt.IsLambdaPlayer ) and 30 or 15 ) ) * 0.1 ), function()
                if !IsValid( self ) or self:GetGameState() < 1 then return end

                if v then
                    gPoker.betType[ self:GetBetType() ].add( plyEnt, -self:GetEntryBet(), self )
                    v.ready = true
                    sound_Play( "mvm/mvm_money_pickup.wav", self:GetPos() )
                end

                local allReady = true
                for _, ply in pairs( self.players ) do
                    if !ply.ready then allReady = false break end
                end
                if allReady then self:nextState() end
            end)
        end
    end

    --

    local function LambdaSetGameState( ent, name, old, new )
        local plys = ent.players
        local stateAdd = ( ent:GetGameType() == 1 and 4 or 0 )

        if new < 1 or new == ( 6 + stateAdd ) then
            local intermissionTime = 5
            
            if ( ent:GetBotsPlaceholder() and ent:getPlayersAmount() or #plys ) < ent:GetMaxPlayers() then
                local foundRealPlayer = false
                local foundLambdaPlayer = false
                
                for _, ply in pairs( plys ) do
                    local plyEnt = Entity( ply.ind )
                    if !IsValid( plyEnt ) then continue end
                    
                    foundRealPlayer = ( foundRealPlayer or plyEnt:IsPlayer() )
                    foundLambdaPlayer = ( foundLambdaPlayer or plyEnt.IsLambdaPlayer )
                end

                if foundLambdaPlayer and !foundRealPlayer then
                    intermissionTime = 10
                end
            end
            
            ent.intermission = intermissionTime

            net.Start( "lambdagpoker_setintermissiontime" )
                net.WriteEntity( ent )
                net.WriteUInt( intermissionTime, 8 )
            net.Broadcast()
        end

        -- Invite some nearby friendly Lambdas on a start of intermission
        if old == #gPoker.gameType[ ent:GetGameType() ].states and new == -1 then
            local plyCount = ( ent:GetBotsPlaceholder() and ent:getPlayersAmount() or #plys )
            local maxPlys = ent:GetMaxPlayers()

            if plyCount < maxPlys then
                for _, lambda in RandomPairs( GetLambdaPlayers() ) do
                    if !LambdaIsValid( lambda ) or lambda.l_PlayingPoker or lambda:InCombat() or lambda:IsPanicking() or !lambda:IsInRange( ent, ( ent.intermission == 10 and 1750 or 800 ) ) then continue end
                    if random( 100 ) > lambda:GetFriendlyChance() or !lambda:IsPokerTableAvailable( ent ) then continue end

                    lambda:SetState( "GoToPokerTable", ent )
                    lambda:CancelMovement()

                    plyCount = ( plyCount + 1 )
                    if plyCount >= maxPlys then break end
                end
            end

            return
        end

        if old <= 2 or new == ( 6 + stateAdd ) then return end

        SimpleTimer( 0, function()
            if !IsValid( ent ) then return end
            local winner = ent:GetWinner()

            for k, v in ipairs( plys ) do
                if v.bot then continue end

                local ply = Entity( v.ind )
                if !IsValid( ply ) or !ply.IsLambdaPlayer then continue end

                local startVal = ( ent:GetBetType() == 1 and ply.l_PokerStartHealth or ent:GetStartValue() )
                if new == ( 7 + stateAdd ) then
                    local voiceline
                    if k == winner then
                        ply.l_PokerQuitAction = 0
                        voiceline = ( ( random( 2 ) == 1 and ( gPoker.betType[ ent:GetBetType() ].get( ply ) + ent:GetPot() ) >= ( startVal * Rand( 1.5, 2.0 ) ) ) and "laugh" or "kill" )
                    else
                        ply.l_PokerQuitAction = random( 1, 3 )
                        voiceline = ( ( random( 2 ) == 1 or gPoker.betType[ ent:GetBetType() ].get( ply ) <= ( startVal * Rand( 0.1, 0.33 ) ) ) and "death" or "taunt" )
                    end

                    ply:SimpleTimer( Rand( 0.1, 1.0 ), function()
                        ply:PlaySoundFile( voiceline )
                    end )
                elseif !ply:IsSpeaking() and random( 3 ) == 1 and random( 100 ) <= ply:GetVoiceChance() then 
                    ply:SimpleTimer( Rand( 0.1, 1.0 ), function()
                        ply:PlaySoundFile( ( gPoker.betType[ ent:GetBetType() ].get( ply ) <= ( startVal * Rand( 0.1, 0.33 ) ) ) and "panic" or "taunt" )
                    end )
                end
            end
        end )
    end

    --

    local function JoinPokerGame( self, ent )
        if !ent.l_Lambdified then
            ent.l_Lambdified = true

            ent.removePlayerFromMatch = LambdaRemoveFromMatch
            ent.revealCommunityCards = LambdaRevealCommunityCards
            ent.entryFee = LambdaEntryFee

            ent:NetworkVar( "Int", 6, "Turn" )
            ent:NetworkVarNotify( "Turn", LambdaSetTurnFunction )
            ent:NetworkVarNotify( "GameState", LambdaSetGameState )

            net.Start( "lambdagpoker_modifydrawfunc" )
                net.WriteEntity( ent )
            net.Broadcast()
        end

        self.l_PlayingPoker = true
        self.l_PokerTable = ent
        self.l_PokerStartHealth = self:Health()
        self:SetState( "SitState" )
        self.l_NextPokerTableCheck = ( CurTime() + random( 45, 180 ) )

        self:SwitchWeapon( "none", true )
        self:PreventWeaponSwitch( true )

        ent:CallOnRemove( "Lambda_GPokerSupport_OnTableRemove" .. self:GetCreationID(), function( ent ) 
            if !IsValid( self ) or !self.l_PlayingPoker then return end
            OnLambdaLeaveMatch( self )
        end )

        ent:Use( self )
    end

    local function IsPokerTableAvailable( self, tbl )
        if tbl:GetBetType() == 1 and self:Health() <= tbl:GetEntryBet() then return false end
        return ( tbl:GetGameState() < 1 and ( tbl:GetBotsPlaceholder() and tbl:getPlayersAmount() or #tbl.players ) < tbl:GetMaxPlayers() )
    end

    local function GoToPokerTable( self, pokerTbl )
        if !IsValid( pokerTbl ) or !self:IsPokerTableAvailable( pokerTbl ) then return true end

        self:MoveToPos( pokerTbl, { run = true, cbTime = 0.1, callback = function()
            if !self:GetState( "GoToPokerTable" ) or !IsValid( pokerTbl ) or !self:IsPokerTableAvailable( pokerTbl ) then return false end
            if !self:IsInRange( pokerTbl, 90 ) then return end

            self:JoinPokerGame( pokerTbl )
            return false
        end } )
    end

    local function LambdaSetEyeAngles() end

    local function LambdaGetBotName( self ) return self:GetLambdaName() end

    --

    local function OnLambdaInitialize( self )
        if ( SERVER ) then
            if CurTime() >= nextWarningT and !ConVarExists( "lambdaplayers_seat_allowsitting" ) then
                PrintMessage( HUD_PRINTTALK, "Lambda GPoker module requires the Seat Module in order to work!" )
                nextWarningT = ( CurTime() + 15 )
            end

            self.l_PlayingPoker = false
            self.l_PokerTable = NULL
            self.l_PokerStartHealth = 0
            self.l_PokerQuitAction = 0
            self.l_NextPokerTableCheck = 0

            self.JoinPokerGame = JoinPokerGame
            self.GoToPokerTable = GoToPokerTable
            self.IsPokerTableAvailable = IsPokerTableAvailable
            self.SetEyeAngles = LambdaSetEyeAngles
        end

        self.GetBotName = LambdaGetBotName
    end

    hook.Add( "LambdaOnInitialize", "Lambda_GPokerSupport_OnLambdaInitialize", OnLambdaInitialize )

    if ( SERVER ) then

        util.AddNetworkString( "lambdagpoker_modifydrawfunc" )
        util.AddNetworkString( "lambdagpoker_setintermissiontime" )

        --

        local function GetPlayerPokerTable( ent )
            if ent:IsPlayer() then 
                local veh = ent:GetVehicle()
                if IsValid( veh ) then
                    local pokerTbl = veh:GetParent()
                    return ( IsValid( pokerTbl ) and pokerTbl:GetClass() == "ent_poker_game" and pokerTbl )
                end
            end

            return ( ent.l_PokerTable )
        end

        --

        local function LookForPokerTables( self )
            if self.l_PlayingPoker or self:InCombat() or self:IsPanicking() or !gamblerNumeroUno:GetBool() then return end

            for _, tbl in RandomPairs( FindByClass( "ent_poker_game" ) ) do
                if !IsValid( tbl ) or !self:IsPokerTableAvailable( tbl ) or !self:IsInRange( tbl, 2000 ) then continue end
                self:SetState( "GoToPokerTable", tbl )
                self:CancelMovement()
                break
            end
        end

        AddUActionToLambdaUA( LookForPokerTables, "LookForPokerTables" )

        --

        local function OnLambdaPokerGrindset( self )
            if self.l_PlayingPoker then return true end
        end

        local function OnLambdaThink( self )
            if CurTime() < self.l_NextPokerTableCheck then return end
            self.l_NextPokerTableCheck = ( CurTime() + 1 )

            local tbl = self.l_PokerTable
            if IsValid( tbl ) then 
                if ( tbl:GetBotsPlaceholder() and tbl:getPlayersAmount() or #tbl.players ) == 1 then
                    tbl:removePlayerFromMatch( self )
                    return
                end
            else
                self.l_PokerQuitAction = 0
            end

            local enemy = self:GetEnemy()
            if IsValid( enemy ) then
                local enemyTbl = GetPlayerPokerTable( enemy )
                if IsValid( enemyTbl ) then
                    self:SetEnemy( NULL )
                    self:CancelMovement()

                    if !self.l_PlayingPoker then
                        self:SetState()
                        if random( 100 ) <= self:GetCombatChance() and self:IsPokerTableAvailable( enemyTbl ) then
                            self:SetState( "GoToPokerTable", enemyTbl )
                        end
                    end
                end

                return
            end

            if !gambleAddiction:GetBool() then return end
            LookForPokerTables( self )
        end

        local function OnLambdaCanTarget( self, target )
            if self.l_PlayingPoker or IsValid( GetPlayerPokerTable( target ) ) then return true end
        end

        local function OnLambdaChangeState( self, old, new )
            if self.l_PlayingPoker and new != "SitState" then return true end
        end

        local function OnLambdaRemoved( self )
            local pTable = self.l_PokerTable
            if IsValid( pTable ) then pTable:removePlayerFromMatch( self ) end
        end

        --

        hook.Add( "LambdaOnThink", "Lambda_GPokerSupport_OnLambdaThink", OnLambdaThink )
        hook.Add( "LambdaOnInjured", "Lambda_GPokerSupport_OnLambdaInjured", OnLambdaPokerGrindset )
        hook.Add( "LambdaOnPreKilled", "Lambda_GPokerSupport_OnLambdaPreKilled", OnLambdaPokerGrindset )
        hook.Add( "LambdaCanTarget", "Lambda_GPokerSupport_OnLambdaCanTarget", OnLambdaCanTarget )
        hook.Add( "LambdaOnChangeState", "Lambda_GPokerSupport_OnLambdaChangeState", OnLambdaChangeState )
        hook.Add( "LambdaOnRemove", "Lambda_GPokerSupport_OnLambdaRemoved", OnLambdaRemoved )
        hook.Add( "LambdaOnOtherKilled", "Lambda_GPokerSupport_OnLambdaOtherKilled", OnLambdaPokerGrindset )

    end

    if ( CLIENT ) then

        local function ModifiedDraw( self )
            self:DrawModel()

            if IsValid( self.deckPot ) then
                if self:GetGameState() > -1 then
                    local ang = EyeAngles()
                    ang.p = 0 
                    ang.r = 0

                    ang:RotateAroundAxis( ang:Up(), -90 )
                    ang:RotateAroundAxis( ang:Forward(), 90 )

                    local text = ""
                    if self:GetGameState() == 0 and timer.Exists( "gpoker_intermission" .. self:EntIndex() ) then 
                        text = ( math.floor( timer.TimeLeft( "gpoker_intermission" .. self:EntIndex() ) ) + 1 )
                    else
                        text = self:GetPot() .. gPoker.betType[ self:GetBetType() ].fix
                    end

                    cam.Start3D2D( ( self.deckPot:GetPos() + self.deckPot:GetUp() * 15 ), ang, 0.2 )
                        draw.SimpleText( text, "gpoker_header", 0, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER )
                    cam.End3D2D()
                end

                self.deckPot:SetLocalAngles( Angle( 0, CurTime() % 360 * 10, 0 ) )
                self.deckPot:SetLocalPos(Vector( 0, 0, math.sin( CurTime() * 3 ) + 39 ) )
                self.deckPot:SetParent( self ) -- Gets NULL'ed when out of PVS
            end

            for _, v in pairs( self.players ) do
                local ent = Entity( v.ind )
                if self:GetPos():Distance( LocalPlayer():GetPos() ) <= 256 then
                    local ang = EyeAngles()
                    ang.p = 0
                    ang.r = 0
                
                    ang:RotateAroundAxis( ang:Up(), -90 )
                    ang:RotateAroundAxis( ang:Forward(), 90 )
                
                    local mult = 15
                    if !ent:IsPlayer() then mult = 45 end
                
                    local pos = ( ent:EyePos() + ent:GetUp() * mult )

                    cam.Start3D2D( pos, ang, 0.15 )
                        surface.SetFont( "gpoker_header" )
                
                        local key = self:getPlayerKey( ent )
                        local margin = 5
                        local nick
                        if ent:IsPlayer() or ent.IsLambdaPlayer then nick = ent:Nick() else nick = "[BOT] " .. ent:GetBotName() end
                        local fontW, fontH = surface.GetTextSize( nick )
                        local bgW, bgH = math.Clamp( fontW, 85, 1000 ) + margin * 2, fontH + margin * 2
                
                        local bgClr = Color( 37, 37, 37, 225 )
                        local txtClr = Color( 255, 255, 255, 255 )
                        local outClr = Color( 71, 133, 198, 255 )
                        local stateClr = txtClr
                
                        surface.SetFont( "gpoker_text" )
                        local state = ""
                        local btmTxtH = 0
                
                        if self:GetGameState() > 0  then
                            if self.players[ key ].strength != nil then
                                state = gPoker.strength[ self.players[ key ].strength ]
                            elseif self.players[ key ].fold then
                                state = "Fold"
                                stateClr = Color( 225, 225, 225, 255 )
                            else
                                state = gPoker.betType[ self:GetBetType() ].get( ent ) .. gPoker.betType[ self:GetBetType() ].fix
                            end
                        
                            local _, btmTxtH = surface.GetTextSize( state )
                            bgH = btmTxtH + bgH
                        end
                    
                    
                        //Change opacity
                        if ( self:GetWinner() > 0 and self:GetWinner() ~= key ) or ( self:GetGameState() > 0 and self:GetGameState() < #gPoker.gameType[ self:GetGameType() ].states and self:GetTurn() ~= key )  then
                            local m = 0.4
                        
                            bgClr = Color( bgClr.r, bgClr.g, bgClr.b, bgClr.a * m )
                            txtClr = Color( txtClr.r, txtClr.g, txtClr.b, txtClr.a * m )
                            stateClr = Color( stateClr.r, stateClr.g, stateClr.b, stateClr.a * m )
                            outClr = Color( outClr.r, outClr.g, outClr.b, outClr.a * m )
                        end
                    
                        if self:GetGameState() == #gPoker.gameType[ self:GetGameType() ].states and self:GetWinner() == key then stateClr = Color( 241, 241,75 ) end
                    
                        draw.NoTexture()
                        surface.SetDrawColor( bgClr:Unpack() )
                        surface.DrawRect( 0 - bgW/2, 0 - bgH/2, bgW, bgH )
                    
                        surface.SetDrawColor( outClr:Unpack() )
                        surface.DrawOutlinedRect( 0 - bgW/2, 0 - bgH/2, bgW, bgH, 2 )
                    
                        draw.SimpleText( nick, "gpoker_header", 0, 0 - bgH/2 + margin, txtClr, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )
                        draw.SimpleText( state, "gpoker_text", 0, 0 - bgH/2 + margin + fontH + btmTxtH/2, stateClr, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP )
                    cam.End3D2D()
                end
            end
        end

        net.Receive( "lambdagpoker_modifydrawfunc", function() 
            local ent = net.ReadEntity()
            if IsValid( ent ) then ent.Draw = ModifiedDraw end
        end )

        net.Receive( "lambdagpoker_setintermissiontime", function()
            local ent = net.ReadEntity()
            if IsValid( ent ) then ent.intermission = net.ReadUInt( 8 ) end
        end )

    end
end

hook.Add( "InitPostEntity", "Lambda_GPokerSupport_InitializeModule", InitializeModule )
if LambdaGPokerInitialized then InitializeModule() end