#pragma once

#include <functional>

#include <QElapsedTimer>
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QString>
#include <QTimer>

#include "rep_zcash_wallet_ui_source.h"
#include "logos_ui_plugin_context.h"

// The Zcash wallet's C++ half: every zcash_wallet_backend call is made here; the QML renders.
// m_readPoll backs up the backend's events; m_jobPoll follows a wallet job, m_sendPoll a send,
// m_migrationJobPoll a migration step.
class ZcashWalletUiBackend : public ZcashWalletUiSimpleSource,
                             public LogosUiPluginContext
{
public:
    void refresh() override;
    void clearAndRefresh() override;

    void setActiveNetwork(QString network) override;
    void openWallet(QString name, QString password) override;
    void createWallet(QString name, QString password) override;
    void restoreWallet(QString name, QString password, QString phrase, int birthdayHeight) override;
    void changePassword(QString oldPassword, QString newPassword) override;
    QString revealSeed(QString password) override;
    QString exportViewingKey(QString password) override;
    void closeWallet() override;

    void prepareSend(QString recipient, QString amountZec, QString memo, bool allowMixedPools) override;
    void shieldAddress(QString address) override;
    void approveSend(QString password) override;
    void cancelSend() override;
    void dismissSend() override;

    void planMigration() override;
    void migrateNow() override;
    void approveMigration(QString password) override;
    void pauseMigration() override;
    void resumeMigration() override;
    void cancelMigration() override;
    void dismissMigrationPlan() override;

    void newAddress() override;
    QString addressValid(QString text) override;
    void refreshHistory() override;
    void showHistoryPage(int page) override;
    QString setProxy(QString proxy) override;
    QString addServer(QString address, QString name) override;
    QString removeServer(QString id) override;
    QString setServerEnabled(QString id, bool enabled) override;
    QString setServerTor(QString id, bool tor) override;
    QString setLocalNode(bool enabled) override;
    void refreshLocalNode() override;

protected:
    void onContextReady() override;

private:
    void say(const QString &line);
    bool ok(const QString &reply, const QString &context);
    bool walletOpen() const;
    QString editServers(const std::function<QString(QJsonArray &)> &edit);
    QString settingsChange(const QString &reply);
    void loadStatus();
    void loadRegistry();
    void loadSync();
    void loadBalances();
    void loadReceive();
    void loadServers();
    void loadServerHealth();
    void clearWalletReads();
    void readHistory(bool quiet);
    void syncHistoryToHeight();
    void track(const QString &reply, const QString &kind, const QString &name);
    void pollJob();
    bool clearSettledSend();
    void startSend(const QString &reply);
    void adoptSend(const QString &id);
    void recoverSend();
    void pollSend();
    void loadMigration();
    void applyMigrationEvent(const QString &payload);
    bool migrationLive() const;
    bool migrationIdle();
    void trackMigration(const QString &reply, const QString &kind);
    void pollMigrationJob();
    void dropPlan();
    QString qrModulesJson(const QString &text) const;

    QTimer m_readPoll;
    QTimer m_jobPoll;
    QTimer m_sendPoll;
    QTimer m_migrationJobPoll;
    QString m_pendingName;
    QString m_qrShieldedFor;
    QString m_qrTransparentFor;
    QElapsedTimer m_healthReadAge;
    QString m_migrationJobId;
    // The plan under review; approval sends these, never anything the view holds.
    QString m_planId;
    QString m_planDigest;
    // migration_status() is read asynchronously, one read at a time.
    bool m_migrationReading = false;
    QElapsedTimer m_migrationReadAge;
    // The scanned height the history on screen describes; -1 is "none read".
    qint64 m_historyHeight = -1;
    QElapsedTimer m_historyReadAge;
    bool m_historyHasPending = false;
    // local_node() is read asynchronously, one read at a time.
    bool m_localNodeReading = false;
    QElapsedTimer m_localNodeReadAge;
};
