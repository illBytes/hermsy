package com.hermes.hermes_app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * Frank's Brief on the home screen. The app saves what to show (see
 * lib/services/brief_widget.dart); this draws it. The greeting and date are
 * worked out here, at draw time, so they stay right between briefs.
 */
class BriefWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, draw(context, widgetData))
        }
    }

    private fun draw(context: Context, data: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.brief_widget)
        views.setOnClickPendingIntent(
            R.id.widget_root,
            HomeWidgetLaunchIntent.getActivity(
                context,
                MainActivity::class.java,
                Uri.parse("frank://brief"),
            ),
        )

        val now = Date()
        views.setTextViewText(
            R.id.date,
            SimpleDateFormat("EEEE, d MMMM", Locale.getDefault()).format(now),
        )
        val name = data.getString("brief_name", null)
        views.setTextViewText(
            R.id.greeting,
            if (name.isNullOrBlank()) greeting() else "${greeting()}, $name",
        )

        val headline = data.getString("brief_headline", null)
        views.setTextViewText(
            R.id.headline,
            headline ?: "Open Hermsy to load your first brief.",
        )
        views.setViewVisibility(
            R.id.headline,
            if (headline == null && data.contains("brief_footer")) View.GONE else View.VISIBLE,
        )

        val rows = listOf(
            Triple(R.id.row1, R.id.row1_lead, R.id.row1_title),
            Triple(R.id.row2, R.id.row2_lead, R.id.row2_title),
            Triple(R.id.row3, R.id.row3_lead, R.id.row3_title),
            Triple(R.id.row4, R.id.row4_lead, R.id.row4_title),
        )
        rows.forEachIndexed { index, (row, lead, title) ->
            val n = index + 1
            val text = data.getString("brief_row${n}_title", null)
            if (text.isNullOrBlank()) {
                views.setViewVisibility(row, View.GONE)
                return@forEachIndexed
            }
            views.setViewVisibility(row, View.VISIBLE)
            views.setTextViewText(title, text)
            views.setTextViewText(lead, data.getString("brief_row${n}_lead", "") ?: "")
            val alert = data.getBoolean("brief_row${n}_alert", false)
            views.setTextColor(
                lead,
                context.getColor(if (alert) R.color.brief_widget_danger else R.color.brief_widget_gold),
            )
        }

        views.setTextViewText(R.id.footer, data.getString("brief_footer", "") ?: "")
        return views
    }

    private fun greeting(): String {
        val hour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        return when (hour) {
            in 5..11 -> "Good morning"
            in 12..16 -> "Good afternoon"
            else -> "Good evening"
        }
    }
}
