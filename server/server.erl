-module(server).
-import(files, [readAccounts/0, writeAccounts/1]).
-import(accounts, [createAccount/4, removeAccount/4, login/4, logout/4, auth/3]).
-import(geometry, [insideCircle/2]).
-import(math, [sin/1, cos/1]).
-export([start/1, start/0, ca/2, ra/2, li/2, lo/2, jo/2, on/0, parseGame/2]).

start(Port) -> register(?MODULE, spawn(fun()-> server(Port) end)).
start() -> register(?MODULE, spawn(fun()-> server(8000) end)).

% -----------------------------------
% Server starts here
% -----------------------------------

server(Port) ->
    ResTCP = gen_tcp:listen(Port, [binary, {packet, line}, {reuseaddr, true}]),
    case ResTCP of
        {error, Reason} -> io:fwrite("Error - Can't create tcp socket\n"), Reason;
        {ok, LSock} ->
            spawn(fun() -> acceptor(LSock) end),
            Party = spawn(fun() -> party([]) end),
            serverLoop(files:readAccounts(), Party, 0)
    end.

% Users -> Map of users : username -> {password, score, loggedIn}
% Party -> Pid of current party
% Ongoing -> Number of ongoing games
serverLoop(Users, Party, Ongoing) ->
    receive
        {create_account, User, Password, From} ->
            NewUsers = accounts:createAccount(Users, User, Password, From),
            serverLoop(NewUsers, Party, Ongoing);
        {remove_account, User, Password, From} ->
            NewUsers = accounts:removeAccount(Users, User, Password, From),
            serverLoop(NewUsers, Party, Ongoing);
        {login, User, Password, From} ->
            NewUsers = accounts:login(Users, User, Password, From),
            serverLoop(NewUsers, Party, Ongoing);
        {logout, User, Password, From} ->
            NewUsers = accounts:logout(Users, User, Password, From),
            serverLoop(NewUsers, Party, Ongoing);
        {join, User, Password, From} ->
            Auth = accounts:auth(Users, User, Password),
            if
                Ongoing == 4 ->
                    From ! full_server;
                Auth ->
                    Party ! {join, User, From};
                true ->
                    From ! invalid_auth
            end,
            serverLoop(Users, Party, Ongoing);
        {start, _From} ->
            NewParty = spawn(fun() -> party([]) end),
            serverLoop(Users, NewParty, Ongoing + 1);
        {online, From} ->
            From ! [Username || {Username, {_Password, _Score, LoggedIn}} <- maps:to_list(Users), LoggedIn],
            serverLoop(Users, Party, Ongoing);
        {leaderboard, From} ->
            UserList = [{Username, Score} || {Username, {_Password, Score, _LoggedIn}} <- maps:to_list(Users)],
            From ! UserList,
            serverLoop(Users, Party, Ongoing);
        {gameover, Winner, From} ->
            From ! winner,
            io:format("Game Over. Winner: ~p ~n", [Winner]),
            Res = maps:get(Winner, Users),
            case Res of
                {badkey, _} -> serverLoop(Users, Party, Ongoing - 1);
                {badmap, _} -> serverLoop(Users, Party, Ongoing - 1);
                {Password, Score, LoggedIn} ->
                    NewUsers = maps:update(Winner, {Password, Score + 1, LoggedIn}, Users),
                    files:writeAccounts(NewUsers),
                    serverLoop(NewUsers, Party, Ongoing - 1)
            end
    end.

% Queue -> List of players in party queue : [{user, pid}, ...]
party(Queue) ->
    Limit = 2,
    % io:fwrite("Party users: "),
    % [io:format("~p ", [User]) || {User, _Pid} <- Queue],
    % io:fwrite("\n"),
    receive
        timeout ->
            game(Queue);
        {join, User, From} ->
            From ! {done, self()},
            NewQueue = Queue ++ [{User, From}],
            case length(NewQueue) of
                Limit ->
                    Self = self(),
                    spawn(fun() -> receive after 10000 -> Self ! timeout end end),
                    party(NewQueue);
                _ ->
                    party(NewQueue)
            end;
        {leave, U, From} ->
            From ! leave_done,
            NewQueue = [{User, Pid} || {User, Pid} <- Queue, User /= U],
            L = length(NewQueue),
            if
                L == Limit - 1 -> receive timeout -> party(NewQueue) end;
                true -> party(NewQueue)
            end
    end.

game(Players) ->
    io:fwrite("Starting game.\n"),
    ?MODULE ! {start, self()},
    [From ! {start, self()}|| {_User, From} <- Players],
    NewPlayers = initGame(Players, []),
    gameTimer(NewPlayers, []).

initGame([], _UsedPositions) -> #{};
initGame([{Player, From}| Players], UsedPositions) ->
    case rand:uniform(3) of
        1 -> Color = red;
        2 -> Color = green;
        3 -> Color = blue
    end,
    X = float(rand:uniform(400)),
    Y = float(rand:uniform(400)),
    case lists:member({X, Y}, UsedPositions) of
        false ->
            Pos = {X, Y},
            PlayerMap = initGame(Players, [Pos | UsedPositions]),
            maps:put(Player, {From, Color, Pos, 1.23, 0, 0}, PlayerMap);

            %maps:put(Player, {From,Color, Pos, angle , Speed, N_Win_Per_Match}, PlayerMap);
            
        true ->
            initGame([{Player, From} | Players], UsedPositions)
    end.

generateCrystals(Crystals, Players) ->
    Number = rand:uniform(100),
    if
        Number == 42 ->
            generateCrystals(Players) ++ Crystals;
        true ->
            Crystals
    end.

generateCrystals([]) -> [];
generateCrystals([{_Player, {_From, _Color, {Px, Py}, _Angle, _Speed,_N_Win}} | T]) ->
    X = rand:uniform(800) - 400,
    Y = rand:uniform(800) - 400,
    case rand:uniform(3) of
        1 -> Color = red;
        2 -> Color = green;
        3 -> Color = blue
    end,
    [{X + Px, Y + Py, Color} | generateCrystals(T)].

gameTimer(Players, Crystals) ->
    Self = self(),
    spawn(fun() -> receive after 40 -> Self ! timeout end end), % tickrate
    {NewPlayers, TempCrystals} = handleGame(Players, Crystals),
    NewCrystals = generateCrystals(TempCrystals, maps:to_list(Players)),
    PlayerInfo = parseGame(maps:to_list(NewPlayers), []),
    case NewCrystals of
        [] -> Info = string:concat(PlayerInfo, "\n");
        _ ->
            CrystalInfo = parseCrystals(NewCrystals, []),
            Info = string:join([PlayerInfo, CrystalInfo], "|")
    end,
    [From ! Info || {_Player, {From, _Color, _Pos, _Angle, _Speed,_N_Win}} <- maps:to_list(NewPlayers)],
    gameLoop(NewPlayers, NewCrystals).

gameLoop(Players, Crystals) ->
    receive
        timeout ->
            gameTimer(Players, Crystals);
        {leave, Username, From} ->
            From ! leave_done,
            handleRemovePlayer(Players, Username, Crystals);
        {Info, _From} ->
            NewPlayers = handleInput(Players, Info),
            gameLoop(NewPlayers, Crystals)
    end.

handleRemovePlayer(Players, Username, Crystals) ->
    NewPlayers = maps:remove(Username, Players),
    case maps:to_list(NewPlayers) of
        [{LastPlayer, {From, _Color, {_X, _Y}, _Angle, _Speed, _N_Win}}] ->
            ?MODULE ! {gameover, LastPlayer, From};
        _ ->
            gameLoop(NewPlayers, Crystals)
    end.

removePlayer(Username, Players, From) ->
    From ! defeat,
    NewPlayers = maps:remove(Username, Players),
    case maps:to_list(NewPlayers) of
        [{LastPlayer, {FromW, _Color, {_X, _Y}, _Angle, _Speed, _N_Win}}] ->
            ?MODULE ! {gameover, LastPlayer, FromW},
            exit(kill);
        _ ->
            NewPlayers
    end.

normalize(X, Y) ->
    Sqrt = math:sqrt(X*X + Y*Y),
    case Sqrt of
        0.0 -> {X, Y};
        _ -> {X / Sqrt, Y / Sqrt}
    end.

handleInput(Players, {Username, Key}) -> 
    Res = maps:get(Username, Players),
    case Res of
        {badmap, _} -> Players;
        {badkey, _} -> Players;
        {From, Color, {OldX, OldY}, Angle, Speed,N_Win} ->
            if  
                Key == "a"->
                    if 
                        (Angle > -(360) ) ->
                            RealAngle= Angle-0.1;
                        true ->
                            RealAngle= 360
                    end,
                    RealSpeed= Speed;
                Key == "A"->
                    if 
                        (Angle> -(360) ) ->
                            RealAngle= Angle-0.1;
                        true ->
                            RealAngle= 360
                    end,
                    
                    RealSpeed= Speed;
                Key == "d"->
                    if 
                        (Angle < ( 360 )) ->
                            RealAngle= Angle+0.1;
                        true ->
                            RealAngle= -360
                    end,

                    RealSpeed= Speed;
                Key == "D"->
                    if 
                        (Angle < (360)) ->
                            RealAngle= Angle+0.1;
                        true ->
                            RealAngle= -360
                    end,
                    RealSpeed= Speed;
                
                Key == "s"->
                    RealAngle=Angle,
                    RealSpeed= Speed+0.1;
                Key == "S"->
                    RealAngle=Angle,
                    RealSpeed= Speed+0.1;
                
                true ->
                    RealAngle=Angle,
                    if 
                        Speed>0 ->
                            RealSpeed= Speed-0.1; 
                        %Como não conseguimos ler 2 teclas ao mesmo tempo implementamos
                        % um sistema de decrescimo de velocidade, que vai diminuindo quando largamos a tecla 's' 
                        % fazendo com que nos possamos alterar a trajetória enquanto nos movimentamos 
                        true ->
                            RealSpeed= Speed
                    end
            end,
            
            {DirX, DirY} = normalize(math:cos(RealAngle), math:sin(RealAngle)),
            {X, Y} = {OldX + DirX * RealSpeed, OldY + DirY * RealSpeed},
            maps:update(Username, {From, Color, {X, Y}, RealAngle, RealSpeed,N_Win}, Players)
    end.


handleGame(Players, Crystals) ->
    CrystalCollisions = findCrystalCollisions(Crystals, maps:to_list(Players)),
    PlayerCollisions  = findColisions(maps:to_list(Players)),
    {NewPlayers, FinalCrystals} = handleCrystalCollisions(CrystalCollisions, Players, Crystals),
    FinalPlayers = handlePlayerCollisions(PlayerCollisions, NewPlayers),
    {FinalPlayers, FinalCrystals}.

handleCrystalCollisions([], Players, Crystals) -> {Players, Crystals};
handleCrystalCollisions([{Player, X, Y, Color} | T], Players, Crystals) ->
    {NewPlayers, NewCrystals} = handleCrystalCollisions(T, Players, Crystals),
    {From, _PColor, Pos, Angle, Speed,N_Win_Match} = maps:get(Player, NewPlayers),
    if
        Color == red ->
            RealSpeed= 0.23;
        Color == green ->
            RealSpeed= Speed*2;
        Color == blue ->
            RealSpeed= Speed*2;
        true ->
            RealSpeed=0.23
        end,
    {maps:update(Player, {From, Color, Pos, Angle, RealSpeed,N_Win_Match}, NewPlayers), [{CX, CY, CColor} || {CX, CY, CColor} <- NewCrystals, not ((CX == X) and (CY == Y))]}.


radians(X) ->
    math:pi() * X  / 180.


handlePlayerCollisions([], Players) -> Players;
handlePlayerCollisions([{P1, P2} | T], Players) ->
    {_From1, _Color1, _Pos1, Angle1, _Speed1, _N_Win_P1} = maps:get(P1, Players),
    {_From2, _Color2, _Pos2, Angle2, _Speed2, _N_Win_P2} = maps:get(P2, Players),
    Angle_90= (math:pi())/2,
    Rad_Angle1=radians(Angle1),
    Rad_Angle2=radians(Angle2),
    %io:format("~p ~n",[Rad_Angle1]),
    %io:format("~p ~n",[Rad_Angle2]),
    if          
        (Rad_Angle1-Rad_Angle2 < (Angle_90)) ->
            PW = P1,
            PL = P2;

        (Rad_Angle1-Rad_Angle2 > -(Angle_90)) ->
            PW = P1,
            PL = P2;

        (Rad_Angle2-Rad_Angle1 < (Angle_90)) ->
            PW = P2,
            PL = P1;

        (Rad_Angle2-Rad_Angle1 > -(Angle_90)) ->
            PW = P2,
            PL = P1;

        true ->
            PW = P1,
            PL = P2

        end,
    {FromW, ColorW, {XW, YW}, AngleW, SpeedW,NW_W} = maps:get(PW, Players),
    {FromL, ColorL, {XL, YL}, AngleL, SpeedL,NW_L} = maps:get(PL, Players),
    {DirX, DirY} = normalize(XW-XL, YW-YL),
    Speed = lists:max([SpeedW, SpeedL]) + 1,

    if
        NW_W+1 == 5 ->
            NewPlayers = maps:update(PW, {FromW, ColorW, {XW+DirX*Speed, YW+DirY*Speed}, 1.23, 0, 0}, Players),
            NewPlayers1 = maps:update(PL, {FromL, ColorL, {XL-DirX*Speed*rand:uniform(50), YL-DirY*Speed*rand:uniform(50)}, 1.23, 0, 0}, NewPlayers),
            FinalPlayers = removePlayer(PL, NewPlayers1, FromL);
        true ->
            NewPlayers = maps:update(PW, {FromW, ColorW, {XW+DirX*Speed, YW+DirY*Speed}, AngleW, SpeedW,NW_W+1}, Players),
            FinalPlayers = maps:update(PL, {FromL, ColorL, {XL-DirX*Speed*rand:uniform(50), YL-DirY*Speed*rand:uniform(50)}, AngleL, SpeedL,NW_L}, NewPlayers)
    end,
    handlePlayerCollisions(T, FinalPlayers).


findCrystalCollisions([], _Players) -> [];
findCrystalCollisions([H | T], Players) -> findCrystalCollisionsAux(H, Players) ++ findCrystalCollisions(T, Players).

findCrystalCollisionsAux(_C, []) -> [];
findCrystalCollisionsAux(C, [H | T]) ->
    {CX, CY, CColor} = C,
    {Player, {_From, _Color, HPos, _HAngle, _Speed, _N_Win}} = H,
    case geometry:crystalInsideCircle({{CX, CY}, 10}, {HPos, 30}) of
        true -> [{Player, CX, CY, CColor} | findCrystalCollisionsAux(C, T)];
        _ -> findCrystalCollisionsAux(C, T)
    end.


findColisions([]) -> [];
findColisions([H|T]) -> findColisions(H, T) ++ findColisions(T).

findColisions(_P, []) -> [];
findColisions(P, [H | T]) ->
    {CPlayer, {_CFrom, _CColor, CPos, _CAngle, _CSpeed,_C_N_Win}} = P,
    {HPlayer, {_HFrom, _HColor, HPos, _HAnlge, _HSpeed,_H_N_Win}} = H,
    case geometry:insideCircle({CPos, 10}, {HPos, 30}) of
        true -> [{CPlayer, HPlayer} | findColisions(P, T)];
        _ -> findColisions(P, T)
    end.

parseGame([], List) -> string:join(List, "|");
parseGame([{Player, {_From, Color, {X, Y}, Angle, _Speed, N_Win}} | Tail], List) ->
    InfoPlayer = string:join([Player, atom_to_list(Color), float_to_list(X), float_to_list(Y), float_to_list(Angle), integer_to_list(N_Win)], " "),
    parseGame(Tail, [InfoPlayer | List]).

parseCrystals([], List) -> string:concat(string:join(List, "|"), "\n");
parseCrystals([{X, Y, Color} | Tail], List) ->
    InfoCrystal = string:join(["<>", atom_to_list(Color), float_to_list(X), float_to_list(Y), "1.23", "0"], " "),
    parseCrystals(Tail, [InfoCrystal | List]).

% -----------------------------------
% Test functions for server
% -----------------------------------

ca(A, B) -> ?MODULE ! {create_account, A, B, self()}, receive Res -> Res end.
ra(A, B) -> ?MODULE ! {remove_account, A, B, self()}, receive Res -> Res end.
li(A, B) -> ?MODULE ! {login, A, B, self()},          receive Res -> Res end.
lo(A, B) -> ?MODULE ! {logout, A, B, self()},         receive Res -> Res end.
jo(A, B) -> ?MODULE ! {join, A, B, self()},           receive Res -> Res end.
on(    ) -> ?MODULE ! {online, self()},               receive Map -> Map end.

% -----------------------------------
% Acceptor and client start here
% -----------------------------------

acceptor(LSock) ->
    ResTCP = gen_tcp:accept(LSock),
    spawn(fun() -> acceptor(LSock) end),
    case ResTCP of
        {error, Reason} -> io:fwrite("Error - Can't connect to tcp.\n"), Reason;
        {ok, Sock} -> client(Sock)
    end.

client(Sock) ->
    receive
        {tcp, _, Data} ->
            String = binary_to_list(string:trim(Data, trailing, "\n")),
            handleClientInput(String, Sock),
            client(Sock)
    end.

handleClientInput(String, Sock) ->
    case string:split(String, ":") of
        ["create_account", Info] ->
            [Username, Password] = string:split(Info, " "),
            ?MODULE ! {create_account, Username, Password, self()},
            receive
                done -> gen_tcp:send(Sock, "done\n");
                user_exists -> gen_tcp:send(Sock, "user_exists\n");
                invalid_password -> gen_tcp:send(Sock, "invalid_password\n")
            end;
        ["remove_account", Info] ->
            [Username, Password] = string:split(Info, " "),
            ?MODULE ! {remove_account, Username, Password, self()},
            receive
                done -> gen_tcp:send(Sock, "done\n");
                invalid_account -> gen_tcp:send(Sock, "invalid_account\n");
                invalid_password -> gen_tcp:send(Sock, "invalid_password\n")
            end;
        ["logout", Info] ->
            [Username, Password] = string:split(Info, " "),
            ?MODULE ! {logout, Username, Password, self()},
            receive
                done -> gen_tcp:send(Sock, "done\n");
                invalid_account -> gen_tcp:send(Sock, "invalid_account\n");
                invalid_password -> gen_tcp:send(Sock, "invalid_password\n")
            end;
        ["login", Info] ->
            [Username, Password] = string:split(Info, " "),
            ?MODULE ! {login, Username, Password, self()},
            receive
                done -> gen_tcp:send(Sock, "done\n");
                invalid_account -> gen_tcp:send(Sock, "invalid_account\n");
                invalid_password -> gen_tcp:send(Sock, "invalid_password\n")
            end;
        ["leaderboard", _] ->
            ?MODULE ! {leaderboard, self()},
            receive
                Users -> 
                    UserList = [string:join([Username, integer_to_list(Score)], " ") || {Username, Score} <- Users],
                    Res = string:join(UserList, "|"),
                    io:format("~w ~p~n", [length(UserList), Res]),
                    gen_tcp:send(Sock, string:join([Res, "\n"], ""))
            end;
        ["online", _] ->
            ?MODULE ! {online, self()},
            receive
                Users ->
                    Res = string:join(Users, " "),
                    io:format("~p~n", [Res]),
                    gen_tcp:send(Sock, string:join([Res, "\n"], ""))
            end;
        ["join", Info] ->
            [Username, Password] = string:split(Info, " "),
            ?MODULE ! {join, Username, Password, self()},
            receive
                {done, Party} ->
                    gen_tcp:send(Sock, "done\n"),
                    clientGame(Sock, Party, Username);
                full_server ->
                    gen_tcp:send(Sock, "full_server\n");
                invalid_auth ->
                    gen_tcp:send(Sock, "invalid_auth\n")
            end;
        _ -> io:fwrite("Incorrect syntax in tcp request.\n")
    end.

clientGame(Sock, Party, Username) ->
    receive
        leave_done -> 
            gen_tcp:send(Sock, "done\n"),
            client(Sock);
        {tcp, _, Data} ->
            [DataString, _] = string:split(binary_to_list(Data), ":"),
            case DataString of
                "leave" -> Party ! {leave, Username, self()};
                _ -> io:fwrite("Incorrect syntax in tcp request.\n")
            end,
            clientGame(Sock, Party, Username);
        {tcp_closed, _} ->
            Party ! {leave, Username, self()};
        {tcp_error, _} ->
            Party ! {leave, Username, self()};
        {start, _From} ->
            gen_tcp:send(Sock, "start\n"),
            clientGameLoop(Sock, Party, Username);
        _ ->
            clientGame(Sock, Party, Username)
    end.

clientGameLoop(Sock, Party, Username) ->
    receive
        leave_done -> 
            gen_tcp:send(Sock, "done\n"),
            client(Sock);
        winner ->
            gen_tcp:send(Sock, "winner\n"),
            client(Sock);
        defeat ->
            gen_tcp:send(Sock, "defeat\n"),
            client(Sock);
        {tcp, _, Data} ->
            DataString = string:trim(binary_to_list(Data), trailing, "\n"),
            case string:split(DataString, ":") of
                ["keyboard", Info]->
                    Party ! {{Username,Info}, self()};
                ["leave", _] -> Party ! {leave, Username, self()}
            end,
            clientGameLoop(Sock, Party, Username);
        {tcp_closed, _} -> Party ! {leave, Username, self()};
        {tcp_error, _} -> Party ! {leave, Username, self()};
        Info ->
            gen_tcp:send(Sock, Info)
    end,
    clientGameLoop(Sock, Party, Username).