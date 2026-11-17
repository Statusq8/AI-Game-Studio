import numpy as np, cv2
from PIL import Image
from scipy import ndimage as ndi
U='/mnt/user-data/uploads/%s-image.webp'
SHEETS=[("7d168199",1,[3,3]),("b5dc5a5b",2,[2,2]),("433d23c8",2,[3]),("ff8d3e4b",3,[2,2]),("868f38ab",3,[2,2]),
        ("275e9680",4,[3,2]),("2a55cda3",4,[2,2]),("8ac66c89",5,[3,2]),("c5055226",5,[3,2]),
        ("cbcc3cea",6,[3,2]),("da84cc29",6,[3,2]),("3c133e03",7,[3,2]),("8a37a5e5",7,[3,3])]
cnt={}
for f,z,rowsn in SHEETS:
    im=np.asarray(Image.open(U%f).convert('RGB')).astype(int)
    H,W=im.shape[:2]
    mx=im.max(2); mn=im.min(2)
    white=(mn>236)&(mx-mn<16)
    lab,_=ndi.label(white)
    border=set(np.unique(np.r_[lab[0],lab[-1],lab[:,0],lab[:,-1]]))-{0}
    fg=~np.isin(lab,list(border))
    # замкнутые белые «окна» (между перекладинами забора, между фонарями) — тоже фон
    hole=(mn>244)&(mx-mn<9)
    hl,hn=ndi.label(hole)
    sizes=ndi.sum(hole,hl,range(1,hn+1))
    for i,sz in enumerate(sizes):
        if sz>1200 and z!=5: fg[hl==i+1]=False
    fg=ndi.binary_opening(fg,iterations=2)
    # строки
    if len(rowsn)==1: bands=[(0,H)]
    else:
        prof=fg.sum(1); mid=H//2; win=prof[int(H*0.3):int(H*0.7)]
        cut=int(H*0.3)+int(np.argmin(win)); bands=[(0,cut),(cut,H)]
    for (a,b),k in zip(bands,rowsn):
        sub=fg[a:b]
        for ks in (21,11,5,1):
            d=cv2.dilate(sub.astype(np.uint8),cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(ks,ks))) if ks>1 else sub.astype(np.uint8)
            l,n=ndi.label(d)
            comps=[]
            for i in range(1,n+1):
                m=(l==i)&sub
                if m.sum()<4000: continue
                xs=np.where(m.any(0))[0]; comps.append([xs.min(),xs.max(),m])
            if len(comps)>=k: break
        if len(comps)<k:
            # разрезать по колонке с минимумом заполненности
            prof=sub.sum(0); allm=sub.copy(); comps=[]
            cuts=[]
            for j in range(1,k):
                lo,hi=int(W*(j/k-0.12)),int(W*(j/k+0.12)); cuts.append(lo+int(np.argmin(prof[lo:hi])))
            edges=[0]+cuts+[W]
            for e0,e1 in zip(edges,edges[1:]):
                m=np.zeros_like(sub); m[:,e0:e1]=sub[:,e0:e1]; xs=np.where(m.any(0))[0]; comps.append([xs.min(),xs.max(),m])
        comps.sort(key=lambda c:c[0])
        while len(comps)>k:  # слить ближайшие по горизонтали
            gaps=[comps[i+1][0]-comps[i][1] for i in range(len(comps)-1)]
            i=int(np.argmin(gaps)); c1,c2=comps[i],comps[i+1]
            comps[i]=[min(c1[0],c2[0]),max(c1[1],c2[1]),c1[2]|c2[2]]; del comps[i+1]
        if len(comps)!=k: print('WARN',f,len(comps),k)
        for x0,x1,m in comps:
            ys,xs=np.where(m); y0,y1=ys.min(),ys.max()
            al=cv2.GaussianBlur(m.astype(np.float32)*255,(0,0),0.9)
            al=np.where(m,np.maximum(al,200),al*0.5)
            full=np.dstack([im[a:b],al]).clip(0,255).astype(np.uint8)
            img=Image.fromarray(full[max(0,y0-4):y1+5,max(0,x0-4):x1+5],'RGBA')
            s=420/max(img.size)
            if s<1: img=img.resize((int(img.width*s),int(img.height*s)),Image.LANCZOS)
            i=cnt.get(z,0); cnt[z]=i+1
            img.save('/tmp/w/zi/zitem_%d_%d.png'%(z,i))
print(cnt)
import glob
fs=sorted(glob.glob('/tmp/w/zi/zitem_*.png'),key=lambda p:[int(x) for x in p.split('_')[-2:][0:1]+[p.split('_')[-1][:-4]]])
c=Image.new('RGBA',(160*11,160*7),(40,40,90,255))
for p in fs:
    z,i=int(p.split('_')[-2]),int(p.split('_')[-1][:-4])
    t=Image.open(p); s=150/max(t.size); t=t.resize((int(t.width*s),int(t.height*s)))
    c.alpha_composite(t,(i*160+5,(z-1)*160+5))
c.convert('RGB').save('/tmp/w/zi_sheet.png')
