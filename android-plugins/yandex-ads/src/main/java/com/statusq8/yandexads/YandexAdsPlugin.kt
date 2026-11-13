package com.statusq8.yandexads

import android.util.Log
import com.yandex.mobile.ads.common.AdError
import com.yandex.mobile.ads.common.AdRequest
import com.yandex.mobile.ads.common.AdRequestError
import com.yandex.mobile.ads.common.ImpressionData
import com.yandex.mobile.ads.common.YandexAds
import com.yandex.mobile.ads.rewarded.Reward
import com.yandex.mobile.ads.rewarded.RewardedAd
import com.yandex.mobile.ads.rewarded.RewardedAdEventListener
import com.yandex.mobile.ads.rewarded.RewardedAdLoadListener
import com.yandex.mobile.ads.rewarded.RewardedAdLoader
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * Минимальный мост Godot ↔ Yandex Mobile Ads: только реклама с вознаграждением.
 * Все вызовы SDK выполняются в главном потоке Android.
 */
class YandexAdsPlugin(godot: Godot) : GodotPlugin(godot) {

    private var rewardedLoader: RewardedAdLoader? = null
    private var rewardedAd: RewardedAd? = null
    private var initialized = false

    override fun getPluginName() = "YandexAds"

    override fun getPluginSignals(): Set<SignalInfo> = setOf(
        SignalInfo("initialized"),
        SignalInfo("rewarded_loaded"),
        SignalInfo("rewarded_failed_to_load", String::class.java),
        SignalInfo("rewarded_shown"),
        SignalInfo("rewarded_failed_to_show", String::class.java),
        SignalInfo("rewarded_dismissed"),
        SignalInfo("rewarded_earned", String::class.java, Int::class.javaObjectType),
    )

    @UsedByGodot
    fun initialize(enableLogging: Boolean) {
        val act = activity ?: return
        runOnUiThread {
            YandexAds.enableLogging(enableLogging)
            YandexAds.initialize(act.applicationContext) {
                initialized = true
                Log.i(TAG, "Yandex Ads SDK initialized")
                emitSignal("initialized")
            }
        }
    }

    @UsedByGodot
    fun isInitialized(): Boolean = initialized

    @UsedByGodot
    fun loadRewarded(adUnitId: String) {
        val act = activity ?: return
        runOnUiThread {
            val loader = rewardedLoader ?: RewardedAdLoader(act).also { rewardedLoader = it }
            loader.loadAd(AdRequest.Builder(adUnitId).build(), object : RewardedAdLoadListener {
                override fun onAdLoaded(rewardedAd: RewardedAd) {
                    this@YandexAdsPlugin.rewardedAd = rewardedAd
                    emitSignal("rewarded_loaded")
                }

                override fun onAdFailedToLoad(adRequestError: AdRequestError) {
                    emitSignal("rewarded_failed_to_load", "${adRequestError.code}: ${adRequestError.description}")
                }
            })
        }
    }

    @UsedByGodot
    fun isRewardedReady(): Boolean = rewardedAd != null

    @UsedByGodot
    fun showRewarded() {
        val act = activity ?: return
        runOnUiThread {
            val ad = rewardedAd
            if (ad == null) {
                emitSignal("rewarded_failed_to_show", "not loaded")
                return@runOnUiThread
            }
            ad.setAdEventListener(object : RewardedAdEventListener {
                override fun onAdShown() = emitSignal("rewarded_shown")
                override fun onAdFailedToShow(adError: AdError) {
                    clearAd()
                    emitSignal("rewarded_failed_to_show", adError.description)
                }
                override fun onAdDismissed() {
                    clearAd()
                    emitSignal("rewarded_dismissed")
                }
                override fun onAdClicked() {}
                override fun onAdImpression(impressionData: ImpressionData?) {}
                override fun onRewarded(reward: Reward) =
                    emitSignal("rewarded_earned", reward.type, reward.amount)
            })
            ad.show(act)
        }
    }

    private fun clearAd() {
        rewardedAd?.setAdEventListener(null)
        rewardedAd = null
    }

    private companion object {
        const val TAG = "YandexAdsPlugin"
    }
}
