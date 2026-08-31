# %%
import os
import geopandas as gpd
import pandas as pd
import numpy as np
import datetime
import csv
import time
from collections import Counter

import matplotlib.pyplot as plt

import statsmodels.api as sm
from sklearn.cluster import KMeans
from scipy.spatial.distance import cdist
from sklearn.metrics import silhouette_samples, silhouette_score
from sklearn.cluster import AgglomerativeClustering
import scipy.cluster.hierarchy as sch

# Set up the logging so that we can see progress
import logging
logging.basicConfig(format='%(asctime)s : %(levelname)s : %(message)s', level=logging.INFO)
# %%

def read_proc_data(**kwargs):
    data_root = kwargs['data_root']
    ind_flood = kwargs['ind_flood']
    
    try:
        agg_info_path = os.path.join(data_root, f'disaster_{ind_flood}_agg_info.csv')
        agg_info = pd.read_csv(agg_info_path)
    except:
        agg_info_path = os.path.join(data_root, ind_flood, f'disaster_{ind_flood}_agg_info.csv')
        agg_info = pd.read_csv(agg_info_path)
    # agg_info = agg_info[agg_info['area_affected'] == 1]

    df_total_dist = agg_info[['geohash_5', 'change_of_users', 'local_date']].copy()
    logging.info(f'Number of affected days: {df_total_dist.local_date.nunique()}')

    # make the table, where each row is a geohash, and each column is a date
    df_total_dist = df_total_dist.pivot(index='geohash_5', columns='local_date', values='change_of_users')
    df_total_dist = df_total_dist.dropna().reset_index()
    logging.info(f'Number of affected geohashes with full data: {df_total_dist.geohash_5.nunique()}')

    df_total_dist_transposed = df_total_dist.set_index('geohash_5').T
    df_total_dist_transposed.index = pd.to_datetime(df_total_dist_transposed.index, format='%Y%m%d')

    return df_total_dist_transposed

def extract_trend_line(df_total_dist_transposed, **kwargs):
    date_list_post = df_total_dist_transposed.index.tolist()
    decomp_observed = pd.DataFrame(index=date_list_post)
    decomp_trend = pd.DataFrame(index=date_list_post)

    # traverse each geohash
    for c in df_total_dist_transposed.columns.tolist():
        try:
            decomposition = sm.tsa.seasonal_decompose(df_total_dist_transposed[c], model='additive')
            decomp_observed[c] = decomposition.observed
            decomp_trend[c] = decomposition.trend
            
        except ValueError:
            print(c)

    date_list_post = decomp_trend.dropna().index.tolist()

    return decomp_trend, date_list_post

def kmeans_clustering(myarray, **kwargs):
    # K-Means Clustering for change (percentage) values 
    # between average users and daily users at the grid cell level
    distortions = []
    K = range(1,20)
    for k in K:
        kmeanModel = KMeans(n_clusters=k, random_state=0).fit(myarray)
        kmeanModel.fit(myarray)
        distortions.append(sum(np.min(cdist(myarray, kmeanModel.cluster_centers_, 'euclidean'), axis=1))/myarray.shape[0])

    plt.figure()
    sup = kwargs['sup']
    plt.suptitle(sup)    
    plt.plot(K, distortions, 'bx-')
    plt.xlabel('k')
    plt.ylabel('Distortion')
    plt.title('The Elbow Method showing the optimal k')

    plt.xticks(np.arange(0, 20, step=1))
    plt.grid(axis='x')

    save_root = kwargs['save_root']
    plt.savefig(os.path.join(save_root, 'elbow_method.png'), dpi=300, bbox_inches='tight')
    plt.close()


def silhouette_analysis(myarray, **kwargs):
    sil = []

    for i in range(2,20):
        km = KMeans(n_clusters=i, random_state=0)
        y_km = km.fit_predict(myarray)
        sil.append(silhouette_score(myarray, y_km))
        
    plt.figure()
    sup = kwargs['sup']
    plt.suptitle(sup)
    plt.plot(range(2,20), sil, marker='o', c='b')
    plt.xticks(np.arange(2, 20, step=1))
    plt.grid(axis='x')

    save_root = kwargs['save_root']
    plt.savefig(os.path.join(save_root, 'silhouette_analysis.png'), dpi=300, bbox_inches='tight')
    plt.close()


def PolygonArea(corners):
    n = len(corners)
    a = 0.0
    for i in range(n):
        j = (i+1) % n
        a += abs(corners[i][0] * corners[j][1] - corners[j][0] * corners[i][1])
        
    area = a / 2.0
    return area

def agglomerative_clustering(myarray, **kwargs):
    n_clusters = kwargs['n_clusters']
    sup = kwargs['sup']

    # Agglomerative clustering dendrogram
    fig, ax = plt.subplots(figsize=(20, 10))
    ax.set_title(sup)
    dendrogram = sch.dendrogram(sch.linkage(myarray, method='ward'), ax=ax)

    save_root = kwargs['save_root']
    plt.savefig(os.path.join(save_root, 'dendrogram.png'), dpi=300, bbox_inches='tight')

    whole_mean = []
    whole_3std1 = []
    whole_3std2 = []
    for d in range(len(myarray[0])):
        A = []
        for n in range(len(myarray)):
            a = myarray[n][d]
            A.append(a)
        whole_mean.append(sum(A)/float(len(A)))    
        whole_3std1.append(3*np.std(A))
        #whole_3std2.append((sum(A)/float(len(A)))-3*np.std(A))

    # Agglomerative Clustering
    model = AgglomerativeClustering(n_clusters=n_clusters, metric='euclidean', linkage='ward')
    model.fit(myarray)
    labels = model.labels_

    labels_N = np.zeros([n_clusters,myarray.shape[0]])
    for n in range(n_clusters):
        for i in range(len(myarray)):
            if labels[i]==n:
                labels_N[n][i]=1
            else:
                labels_N[n][i]=0

    meancenter = np.zeros([n_clusters ,myarray.shape[1]])
    std = np.zeros([n_clusters,myarray.shape[1]])

    for n in range(len(labels_N)):
        for i in range(len(myarray[0])):
            A=[]
            for j in range(len(myarray)):
                a=myarray[j][i]*labels_N[n][j]
                A.append(a)
            meancenter[n][i] = sum(A)/sum(labels_N[n])
            std[n][i] = np.std(np.trim_zeros(A))
    
    # Get unique values and their counts
    unique_values, counts = np.unique(labels, return_counts=True)
    logging.info(f"Unique values: {unique_values}")
    logging.info(f"Counts: {counts}")
            
    myarray_adjusted = []
    for i in range(len(myarray)):
        for n in range(n_clusters):
    #         if group_Kc3[i]==n:
            if labels[i]==n:
                #plt.plot(yymmddhh_list, myarray[i]-whole_mean, color=colors[n], alpha=0.3, linewidth=linewidths[n])
                myarray_adjusted.append(myarray[i]-whole_mean)
    
    # Mapping & Merge dataset
    list_ctids = kwargs['list_ctids']
    date_list_post = kwargs['date_list_post']
    re = pd.DataFrame(myarray_adjusted)
    re.index = list_ctids
    re.columns = [date.strftime('%Y-%m-%d') for date in date_list_post]
    re['label'] = labels
    re = re.reset_index()

    save_root = kwargs['save_root']
    re.to_csv(os.path.join(save_root, 'clustering_result.csv'), index=False)

    return re


def clustering_pipeline(decomp_trend, **kwargs):
    # Timeseires with numpy array
    myarray = np.transpose(decomp_trend.dropna().to_numpy())
    logging.info(f'Available geohashes (cell * days): {myarray.shape}')
    list_ctids = decomp_trend.columns.tolist()
    kwargs['list_ctids'] = list_ctids

    # K-means clustering
    kmeans_clustering(myarray, **kwargs)

    # Silhouette analysis
    silhouette_analysis(myarray, **kwargs)

    # Agglomerative clustering
    re = agglomerative_clustering(myarray, **kwargs)

    return re

def viz_all_groups(viz_args, **kwargs):
    n_clusters = kwargs['n_clusters']
    save_root = kwargs['save_root']

    sup = kwargs['sup']
    yymmdd_list = viz_args['yymmdd_list']
    yymmdd_list_str = viz_args['yymmdd_list_str']
    myarray = viz_args['myarray']
    labels = viz_args['labels']
    labels_N = viz_args['labels_N']
    meancenter4 = viz_args['meancenter4']
    std4 = viz_args['std4']

    fig = plt.figure(figsize=(10,5), dpi=300)
    plt.suptitle(sup, fontsize=16)
    plt.xticks(yymmdd_list, yymmdd_list_str, rotation=90, fontsize=9)
    # Match by_group.png from 2c_plot_cluster_trends.ipynb: teal is always the
    # decrease cluster, orange always the increase cluster. Cluster label
    # integers are not ordered consistently across events, so derive which label
    # is which from the sign of each cluster's mean trend rather than indexing
    # the palette by raw label.
    palette = ['#66a7a6', '#e16503']
    if n_clusters != 2:
        raise ValueError(
            "This figure uses a two-colour decrease/increase palette; "
            f"got n_clusters={n_clusters}."
        )
    cluster_mean = [myarray[labels == n].mean() for n in range(n_clusters)]
    decrease_label = int(np.argmin(cluster_mean))
    increase_label = int(np.argmax(cluster_mean))
    if decrease_label == increase_label:
        raise ValueError(
            "Cannot tell the decrease cluster from the increase cluster; "
            f"cluster means are {cluster_mean}."
        )
    colors = [None] * n_clusters
    colors[decrease_label] = palette[0]
    colors[increase_label] = palette[1]

    for i in range(len(myarray)):
        for n in range(n_clusters):
            if labels[i]==n:
                plt.plot(yymmdd_list, myarray[i], color=colors[n], alpha=0.4, linewidth=0.1)

        
    for i in range(len(labels_N)):
        plt.plot(yymmdd_list, meancenter4[i], marker='o', markersize=3, color=colors[i], linewidth=1.5,
                label = "%s neighborhoods"%(Counter(labels)[i]))

        # fill_between
        x1 = np.arange(len(std4[i]))
        f1 = meancenter4[i]+std4[i]
        f2 = meancenter4[i]-std4[i]
        plt.fill_between(x1, f1, f2, alpha=0.2, color=colors[i])
        
    plt.plot(yymmdd_list, [0]*myarray.shape[1], color='Black', linewidth = 1, linestyle='--', alpha=0.6)
    plt.legend(loc = 'lower left')

    y_max = max(myarray.max(), abs(myarray.min()))
    plt.ylim(-y_max,y_max)
    plt.grid(False)

    plt.savefig(os.path.join(save_root, 'all_groups.png'), dpi=300, bbox_inches='tight')
    plt.close()


def viz_by_group(viz_args, **kwargs):
    n_clusters = kwargs['n_clusters']
    save_root = kwargs['save_root']

    yymmdd_list = viz_args['yymmdd_list']
    yymmdd_list_str = viz_args['yymmdd_list_str']
    myarray = viz_args['myarray']
    labels = viz_args['labels']
    labels_N = viz_args['labels_N']
    meancenter4 = viz_args['meancenter4']
    std4 = viz_args['std4']

    def plot_result_group(g):
    #     plt.xticks(yymmdd_list,yymmdd_list_str, rotation=90, fontsize=9)
        colors = ['crimson', 'darkblue', 'grey', 'dodgerblue']

        for i in range(len(myarray)):
            for n in range(n_clusters):
                if labels[i]==g:
                    plt.plot(yymmdd_list, myarray[i], color=colors[g], alpha=0.1, linewidth=0.05)

        for i in range(len(labels_N)):
            if i == g:
                plt.plot(yymmdd_list, meancenter4[i], marker='o' ,markersize=3, color=colors[g], linewidth=1.5,
                        label = "%s neighborhoods"%(Counter(labels)[i]))

                # fill_between
                x1 = np.arange(len(std4[i]))
                f1 = meancenter4[i]+std4[i]
                f2 = meancenter4[i]-std4[i]
                plt.fill_between(x1, f1, f2, alpha=0.2, color=colors[g])
                plt.fill_between(x1, meancenter4[i], alpha=0.6, color='k')

        plt.plot(yymmdd_list, [0]*myarray.shape[1], color='Black', linewidth = 1, linestyle='--', alpha=0.6)
        plt.legend(loc = 'upper right')
        y_max = max(myarray.max(), abs(myarray.min()))
        plt.ylim(-y_max,y_max)
        plt.grid(linewidth=0.5, alpha=0.5)
    
    sup = kwargs['sup']
    fig = plt.figure(figsize=(16,8), dpi=300)
    plt.suptitle(sup, fontsize=16)

    plt.subplot(2,2,1)
    plot_result_group(2)

    plt.subplot(2,2,2)
    plot_result_group(0)

    plt.subplot(2,2,3)
    plot_result_group(3)

    plt.subplot(2,2,4)
    plot_result_group(1)

    plt.savefig(os.path.join(save_root, 'by_group.png'), dpi=300, bbox_inches='tight')
    plt.close()

def viz_all_trends(viz_args, **kwargs):
    n_clusters = kwargs['n_clusters']
    save_root = kwargs['save_root']

    yymmdd_list = viz_args['yymmdd_list']
    yymmdd_list_str = viz_args['yymmdd_list_str']
    myarray = viz_args['myarray']
    sup = kwargs['sup']

    fig = plt.figure(figsize=(15,4), dpi=300)
    plt.suptitle(sup, fontsize=16)
    plt.xticks(yymmdd_list,yymmdd_list_str, rotation=90, fontsize=9)

    for i in range(len(myarray)):
        plt.plot(yymmdd_list, myarray[i], color='grey', alpha=0.2, linewidth=0.2)
        
    plt.plot(yymmdd_list, [0]*myarray.shape[1], color='Black', linewidth = 1, linestyle='--', alpha=0.6)
    y_max = max(myarray.max(), abs(myarray.min()))
    plt.ylim(-y_max,y_max)
    plt.grid(False)

    plt.savefig(os.path.join(save_root, 'all_trends.png'), dpi=300, bbox_inches='tight')
    plt.close()

def viz_pipeline(re, **kwargs):
    n_clusters = kwargs['n_clusters']

    myarray = re.iloc[:, 1:-1].to_numpy()
    labels = re['label'].to_numpy()

    labels_N = np.zeros([n_clusters,myarray.shape[0]])
    for n in range(n_clusters):
        for i in range(len(myarray)):
            if labels[i]==n:
                labels_N[n][i]=1
            else:
                labels_N[n][i]=0

    meancenter4 = np.zeros([n_clusters,myarray.shape[1]])
    std4 = np.zeros([n_clusters,myarray.shape[1]])

    for n in range(len(labels_N)):
        for i in range(len(myarray[0])):
            A=[]
            for j in range(len(myarray)):
                a=myarray[j][i]*labels_N[n][j]
                A.append(a)
            meancenter4[n][i] = sum(A)/sum(labels_N[n])
            std4[n][i] = np.std(np.trim_zeros(A))
    
    yymmdd_list = range(len(myarray[1]))
    yymmdd_list_str = re.columns[1:-1].tolist()

    viz_args = {
        'myarray': myarray,
        'labels': labels,
        'labels_N': labels_N,
        'meancenter4': meancenter4,
        'std4': std4,
        'yymmdd_list': yymmdd_list,
        'yymmdd_list_str': yymmdd_list_str,
    }

    viz_all_groups(viz_args, **kwargs)
    # by_group.png is produced by 2c_plot_cluster_trends.ipynb; this function is
    # the four-cluster layout from the earlier analysis and is not used at k=2.
    # viz_by_group(viz_args, **kwargs)
    viz_all_trends(viz_args, **kwargs)


def process_pipeline(**kwargs):
    # suptitle
    ind_flood = kwargs['ind_flood']
    start_end = kwargs['in_flood_start_end'][ind_flood]
    sup = f'{ind_flood} ({start_end[0]} - {start_end[1]})'
    kwargs['sup'] = sup

    data_root = kwargs['data_root']
    clustering_res_path = os.path.join(data_root, 'clustering_result.csv')

    # if not os.path.exists(clustering_res_path):
    df_total_dist_transposed = read_proc_data(**kwargs)
    decomp_trend, date_list_post = extract_trend_line(df_total_dist_transposed, **kwargs)
    kwargs['date_list_post'] = date_list_post
    res = clustering_pipeline(decomp_trend, **kwargs)
    # else:
    #     res = pd.read_csv(clustering_res_path)

    viz_pipeline(res, **kwargs)

    return res

# %%

if __name__ == '__main__':
    in_flood_start_end = {
        '4775': ('2019-07-01', '2019-07-05'),
        '4859': ('2020-01-01', '2020-01-09'),
    }
    in_flood_no = [
        '4775',
        '4859',
    ]
    n_clusters = 2
    # DATA_ROOT and OUT_ROOT set the input and output roots; the defaults are
    # ../data and ../outputs.
    data_root = os.environ.get('DATA_ROOT', '../data')
    out_root = os.environ.get('OUT_ROOT', '../outputs')

    params = {
        'data_root': data_root,
        'n_clusters': n_clusters,
        'in_flood_start_end': in_flood_start_end,
    }
    for ind_flood in in_flood_no:
        logging.info(f'Processing {ind_flood}...')
        params['ind_flood'] = ind_flood

        ind_save_root = os.path.join(out_root, ind_flood, f"cluster_{n_clusters}")
        os.makedirs(ind_save_root, exist_ok=True)
        params['save_root'] = ind_save_root
        params['data_root'] = data_root

        res = process_pipeline(**params)

