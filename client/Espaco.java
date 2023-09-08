import processing.core.PApplet;

import java.util.ArrayList;
import java.util.List;


public class Espaco {
    public Peca me;
    public List<Peca> Pecas = new ArrayList<>();

    public synchronized Peca getMe() {
        return this.me;
    }

    public synchronized void setEspaco(Peca p, List<Peca> lp) {
        this.me = p;
        this.Pecas = lp;
    }

    public synchronized void setEspaco(String username, String response){
        this.Pecas.clear();
        String[] positionsString = response.split("\\|");
        for(String PecaString: positionsString) {
            String[] PecaInfo = PecaString.split(" ");
            Peca Peca = new Peca(PecaInfo[0], PecaInfo[1], Float.parseFloat(PecaInfo[2]), Float.parseFloat(PecaInfo[3]), Float.parseFloat(PecaInfo[4]), Integer.parseInt(PecaInfo[5]));
            
            if(Peca.username.equals(username))
                this.me = Peca;
            else
                this.Pecas.add(Peca);
        }
        for(Peca p : this.Pecas){
            p.x -= me.x;
            p.y -= me.y;
        }
        me.x = 0;
        me.y = 0;
    }

    public synchronized Tuple<Peca,List<Peca>> getEspaco() {
        return new Tuple<>(this.me, this.Pecas);
    }
}
